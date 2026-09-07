import AppKit
import CoreImage
import CoreVideo
import Foundation
import Vision

/// Semantic label for a selection matte. Providers may support a subset.
enum SemanticClass: String, Sendable, Hashable, CaseIterable {
    case person
    case face
    case skin
    case hair
    case sky
    case water
    case foliage
    case building
    case unknown
}

/// Where a `SelectionMask` came from — keeps CoreML / point-prompt ready without API churn.
enum SelectionSource: Hashable, Sendable {
    case visionPerson
    case coreML(modelID: String)
    case pointPrompt
}

/// Vision / export quality for person segmentation.
enum SelectionQuality: String, Sendable, Hashable {
    /// Live preview — Vision `.balanced`, typically on a downscaled working image.
    case preview
    /// Settle / export — Vision `.accurate`.
    case accurate
}

/// How the surface composites the current matte (Select-and-Mask style view modes).
enum SelectionDisplayMode: String, Sendable, Hashable, CaseIterable {
    case none
    /// Selected region full strength; everything else dimmed.
    case onionSkin
    /// Dashed contour only; photo otherwise untouched.
    case marchingAnts
    /// Rubylith-style wash over the *unselected* area.
    case overlay
    /// Subject on solid black.
    case onBlack
    /// Subject on solid white.
    case onWhite
    /// Matte as grayscale (white = selected).
    case blackAndWhite
    /// Subject cut out over a transparency checkerboard.
    case onLayers

    /// Modes the user can cycle with F (excludes `.none`).
    static var previewCycle: [SelectionDisplayMode] {
        [.onionSkin, .marchingAnts, .overlay, .onBlack, .onWhite, .blackAndWhite, .onLayers]
    }

    var menuTitle: String {
        switch self {
        case .none: return "None"
        case .onionSkin: return "Onion Skin"
        case .marchingAnts: return "Marching Ants"
        case .overlay: return "Overlay"
        case .onBlack: return "On Black"
        case .onWhite: return "On White"
        case .blackAndWhite: return "Black & White"
        case .onLayers: return "On Layers"
        }
    }

    func nextInPreviewCycle() -> SelectionDisplayMode {
        let cycle = Self.previewCycle
        guard let idx = cycle.firstIndex(of: self) else { return cycle[0] }
        return cycle[(idx + 1) % cycle.count]
    }
}

/// Global matte edge refine (Select and Mask–style). Display + cutout export only.
struct SelectionRefineParameters: Equatable, Sendable {
    /// Softens jagged / irregular edges (0…1).
    var smooth: Double = 0
    /// Softens the transition / blurs the boundary (0…1).
    var feather: Double = 0
    /// Sharpens the transition after feathering (0…1).
    var contrast: Double = 0
    /// Contracts (−) or expands (+) the boundary (−1…1).
    var shiftEdge: Double = 0
    /// Fringe color spill reduction on cutout export (0…1). Display preview optional.
    var decontaminate: Double = 0

    static let identity = SelectionRefineParameters()

    var isIdentity: Bool {
        abs(smooth) < 0.0005
            && abs(feather) < 0.0005
            && abs(contrast) < 0.0005
            && abs(shiftEdge) < 0.0005
            && abs(decontaminate) < 0.0005
    }

    /// Applies refine in Photoshop-ish order: Smooth → Feather → Contrast → Shift Edge.
    /// Decontaminate is applied on the photo (cutout path), not the matte.
    func applying(to maskCI: CIImage, extent: CGRect) -> CIImage {
        let matteIdentity = abs(smooth) < 0.0005
            && abs(feather) < 0.0005
            && abs(contrast) < 0.0005
            && abs(shiftEdge) < 0.0005
        guard !matteIdentity else { return maskCI.cropped(to: extent) }
        var current = maskCI.clampedToExtent()

        if smooth > 0.0005 {
            // Light blur + mild morphology closes jaggies without melting the subject.
            let radius = Float(smooth * 3.5)
            current = current
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: radius * 0.35])
                .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius * 0.35])
        }

        if feather > 0.0005 {
            let radius = Float(feather * 18)
            current = current.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
        }

        if contrast > 0.0005 {
            // Snap soft edges toward binary around mid-gray.
            let amount = 1.0 + contrast * 4.0
            current = current.applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: amount,
                kCIInputBrightnessKey: 0.0,
                kCIInputSaturationKey: 0.0
            ])
        }

        if abs(shiftEdge) > 0.0005 {
            let radius = Float(abs(shiftEdge) * 14)
            if shiftEdge > 0 {
                current = current.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
            } else {
                current = current.applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: radius])
            }
        }

        return current.cropped(to: extent)
    }
}

/// Single-channel (or alpha) matte in image pixel space.
struct SelectionMask: Sendable {
    let cgImage: CGImage
    /// Extent in the source image’s pixel coordinate system.
    let extent: CGRect
    let confidence: Float
    let semanticClass: SemanticClass
    let source: SelectionSource

    var ciImage: CIImage {
        CIImage(cgImage: cgImage)
    }

    /// Scales the matte to match a target image extent (preview vs full-res).
    func ciImageMatching(extent target: CGRect) -> CIImage {
        let mask = ciImage
        let sx = target.width / max(mask.extent.width, 1)
        let sy = target.height / max(mask.extent.height, 1)
        var scaled = mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        if scaled.extent.origin != target.origin {
            scaled = scaled.transformed(
                by: CGAffineTransform(
                    translationX: target.minX - scaled.extent.minX,
                    y: target.minY - scaled.extent.minY
                )
            )
        }
        return scaled.cropped(to: target)
    }
}

enum SelectionError: Error, Equatable {
    case unsupportedClass(SemanticClass)
    case emptyResult
    case invalidImage
    case pointMiss
    /// CoreML weights missing / not yet downloaded — caller may fall back to Vision.
    case modelNotReady
}

/// Point/box prompt for class-agnostic SAM-style providers (ADR 0005).
struct SelectionPrompt: Equatable, Sendable {
    var positivePoints: [CGPoint]
    var negativePoints: [CGPoint]
    /// Axis-aligned box in image pixel space (optional).
    var box: CGRect?

    static let empty = SelectionPrompt(positivePoints: [], negativePoints: [], box: nil)

    static func point(_ point: CGPoint) -> SelectionPrompt {
        SelectionPrompt(positivePoints: [point], negativePoints: [], box: nil)
    }

    var isEmpty: Bool {
        positivePoints.isEmpty && negativePoints.isEmpty && box == nil
    }
}

/// Generalized on-device selection. Vision person is the first conformer;
/// CoreML semantic / point-prompt providers plug in later without rewriting callers.
protocol SelectionProvider: Sendable {
    var providerID: String { get }

    func selectRegion(
        in image: CIImage,
        at point: CGPoint,
        quality: SelectionQuality
    ) async throws -> SelectionMask

    func selectClass(
        in image: CIImage,
        class semanticClass: SemanticClass,
        quality: SelectionQuality
    ) async throws -> SelectionMask

    /// Prompt-driven select (points / box). Preferred entry for SAM-class engines.
    func select(
        in image: CIImage,
        prompt: SelectionPrompt,
        quality: SelectionQuality
    ) async throws -> SelectionMask
}

/// Preview / export compositing for selection mattes (display-only; never mutates the file).
enum SelectionCompositor {
    /// Classic Quick Mask / rubylith over the unselected area.
    private static let overlayFill = CIColor(
        red: 0.92,
        green: 0.18,
        blue: 0.28,
        alpha: 0.48
    )

    static func apply(
        image: CIImage,
        mask: SelectionMask,
        mode: SelectionDisplayMode,
        appearance: NSAppearance,
        refine: SelectionRefineParameters = .identity,
        antsPhase: CGFloat = 0
    ) -> CIImage {
        apply(
            image: image,
            maskCI: mask.ciImageMatching(extent: image.extent),
            mode: mode,
            appearance: appearance,
            refine: refine,
            antsPhase: antsPhase
        )
    }

    static func apply(
        image: CIImage,
        maskCI: CIImage,
        mode: SelectionDisplayMode,
        appearance: NSAppearance,
        refine: SelectionRefineParameters = .identity,
        antsPhase: CGFloat = 0
    ) -> CIImage {
        guard mode != .none else { return image }
        let extent = image.extent
        let mask = refine.applying(to: maskCI.cropped(to: extent), extent: extent)

        switch mode {
        case .none:
            return image
        case .onionSkin:
            return onionSkin(image: image, mask: maskForBlend(mask, extent: extent), extent: extent)
        case .marchingAnts:
            // Soft dim only — exact dashed contour is drawn in view space (CAShapeLayer).
            let blendMask = maskForBlend(mask, extent: extent)
            return onionSkin(image: image, mask: blendMask, extent: extent, veilAlpha: 0.28)
        case .overlay:
            let wash = CIImage(color: overlayFill).cropped(to: extent)
            return blend(foreground: image, background: wash, mask: maskForBlend(mask, extent: extent), extent: extent) ?? image
        case .onBlack:
            let backdrop = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
            return blend(foreground: image, background: backdrop, mask: maskForBlend(mask, extent: extent), extent: extent) ?? image
        case .onWhite:
            let backdrop = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: extent)
            return blend(foreground: image, background: backdrop, mask: maskForBlend(mask, extent: extent), extent: extent) ?? image
        case .blackAndWhite:
            return grayscaleMatte(mask: mask, extent: extent)
        case .onLayers:
            let backdrop = checkerboardBackdrop(extent: extent, appearance: appearance)
            return blend(foreground: image, background: backdrop, mask: maskForBlend(mask, extent: extent), extent: extent) ?? image
        }
    }

    /// Alpha cutout: subject opaque, outside transparent (for PNG export).
    static func cutoutWithAlpha(
        image: CIImage,
        mask: SelectionMask,
        refine: SelectionRefineParameters = .identity
    ) -> CIImage {
        let extent = image.extent
        let maskCI = refine.applying(
            to: mask.ciImageMatching(extent: extent),
            extent: extent
        )
        let cleanedPhoto = SelectionDecontaminate.apply(
            image: image,
            mask: maskCI,
            amount: refine.decontaminate,
            extent: extent
        )
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: extent)
        return blend(foreground: cleanedPhoto, background: clear, mask: maskCI, extent: extent) ?? cleanedPhoto
    }

    private static func blend(
        foreground: CIImage,
        background: CIImage,
        mask: CIImage,
        extent: CGRect
    ) -> CIImage? {
        guard let blend = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: foreground,
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask
        ])?.outputImage else {
            return nil
        }
        return blend.cropped(to: extent)
    }

    /// MobileSAM / Metal mattes are often opaque RGBA with the signal in RGB.
    /// `CIBlendWithMask` prefers alpha — convert luminance → alpha so soft mattes blend correctly.
    private static func maskForBlend(_ mask: CIImage, extent: CGRect) -> CIImage {
        mask
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
            .applyingFilter("CIMaskToAlpha")
            .cropped(to: extent)
    }

    private static func multiply(_ a: CIImage, _ b: CIImage, extent: CGRect) -> CIImage {
        guard let out = CIFilter(name: "CIMultiplyCompositing", parameters: [
            kCIInputImageKey: a,
            kCIInputBackgroundImageKey: b
        ])?.outputImage else {
            return a.cropped(to: extent)
        }
        return out.cropped(to: extent)
    }

    private static func onionSkin(
        image: CIImage,
        mask: CIImage,
        extent: CGRect,
        veilAlpha: CGFloat = 0.58
    ) -> CIImage {
        let veil = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: veilAlpha)).cropped(to: extent)
        let dimmed = veil.composited(over: image).cropped(to: extent)
        return blend(foreground: image, background: dimmed, mask: mask, extent: extent) ?? image
    }

    private static func grayscaleMatte(mask: CIImage, extent: CGRect) -> CIImage {
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: extent)
        return blend(foreground: white, background: black, mask: maskForBlend(mask, extent: extent), extent: extent) ?? black
    }

    /// Binary plate from a soft matte. Threshold ~0.25 so soft MobileSAM interiors survive.
    static func hardBinaryMatte(mask: CIImage, extent: CGRect) -> CIImage {
        mask
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 20, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 20, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 20, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                // 20x - 5 → binary cut near 0.25 (soft SAM often sits below 0.5).
                "inputBiasVector": CIVector(x: -5, y: -5, z: -5, w: 0)
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .cropped(to: extent)
    }

    private static func checkerboardBackdrop(extent: CGRect, appearance: NSAppearance) -> CIImage {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let light: CIColor
        let dark: CIColor
        if isDark {
            light = CIColor(red: 0.28, green: 0.28, blue: 0.30, alpha: 1)
            dark = CIColor(red: 0.16, green: 0.16, blue: 0.18, alpha: 1)
        } else {
            light = CIColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 1)
            dark = CIColor(red: 0.76, green: 0.76, blue: 0.78, alpha: 1)
        }
        let cell: CGFloat = 10
        guard let board = CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputCenter": CIVector(x: 0, y: 0),
            "inputColor0": light,
            "inputColor1": dark,
            "inputWidth": cell,
            "inputSharpness": 1.0
        ])?.outputImage?.cropped(to: extent) else {
            return CIImage(color: dark).cropped(to: extent)
        }
        return board
    }
}

/// Canonical matte shape for every downstream consumer: opaque alpha, coverage in luminance.
enum SelectionMatteNormalization {
    /// Coverage as an opaque grayscale matte.
    ///
    /// MobileSAM returns premultiplied mattes carrying coverage in *alpha*; their RGB sits
    /// near mid-grey (sRGB 0.53), which Core Image linearises to ~0.24 — right on the binary
    /// threshold, so any luminance-based step (polish, blend, contour) sees a near-empty
    /// matte. Vision is the opposite: opaque alpha with coverage already in luminance, and
    /// those mattes pass through untouched.
    static func opaqueCoverage(matte: CIImage, extent: CGRect, context: CIContext) -> CIImage {
        guard carriesCoverageInAlpha(matte, extent: extent, context: context) else { return matte }
        return matte
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
            .cropped(to: extent)
    }

    /// True when alpha varies — i.e. alpha is the coverage channel, not a constant 1.
    static func carriesCoverageInAlpha(
        _ matte: CIImage,
        extent: CGRect,
        context: CIContext
    ) -> Bool {
        let average = matte.applyingFilter("CIAreaAverage", parameters: [
            kCIInputExtentKey: CIVector(cgRect: extent)
        ])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            average,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return pixel[3] < 250
    }
}

/// Builds a Vision contour path for view-space marching ants (exact subject outline).
enum SelectionAntsContour {
    /// Normalized CGPath (0…1, Vision bottom-leading) for the hard matte silhouette.
    static func normalizedPath(
        mask: SelectionMask,
        refine: SelectionRefineParameters = .identity,
        context: CIContext
    ) -> CGPath? {
        let extent = mask.extent.integral
        guard extent.width > 2, extent.height > 2 else { return nil }
        var matte = refine.applying(to: mask.ciImageMatching(extent: extent), extent: extent)
        matte = SelectionMatteNormalization.opaqueCoverage(
            matte: matte,
            extent: extent,
            context: context
        )
        matte = SelectionCompositor.hardBinaryMatte(mask: matte, extent: extent)

        // Cap for Vision — contour quality stays high; overlay scales to the photo frame.
        let maxEdge: CGFloat = 768
        let longEdge = max(extent.width, extent.height)
        if longEdge > maxEdge {
            let scale = maxEdge / longEdge
            matte = matte.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let plateExtent = matte.extent.integral
        matte = SelectionCompositor.hardBinaryMatte(mask: matte, extent: plateExtent)
        matte = cleanedHardMatte(matte, extent: plateExtent)
        guard let cg = context.createCGImage(matte, from: plateExtent) else { return nil }
        return normalizedPath(fromHardMatte: cg)
    }

    /// Morphological close → open. Fills pinholes and drops speckles that would otherwise
    /// become dozens of tiny noise contours (scattered dashes instead of one outline).
    static func cleanedHardMatte(_ hardMatte: CIImage, extent: CGRect) -> CIImage {
        let radius = max(1.5, min(extent.width, extent.height) / 220.0)
        return hardMatte.clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: radius * 2])
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
    }

    /// Silhouette outline only — noise contours are discarded by normalized bounding-box size.
    static func normalizedPath(fromHardMatte cgImage: CGImage) -> CGPath? {
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 1.0
        request.detectsDarkOnLight = false
        request.maximumImageDimension = 768
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }

        let combined = CGMutablePath()
        var appended = false
        for contour in observation.topLevelContours {
            appended = append(contour, to: combined, minimumSpan: 0.08) || appended
        }
        guard appended else { return nil }
        return combined
    }

    /// Appends a contour (and its holes) when it spans enough of the frame to be real structure.
    private static func append(
        _ contour: VNContour,
        to path: CGMutablePath,
        minimumSpan: CGFloat
    ) -> Bool {
        var appended = false
        let contourPath = contour.normalizedPath
        let box = contourPath.boundingBox
        if contour.pointCount >= 12,
           max(box.width, box.height) >= minimumSpan {
            path.addPath(contourPath)
            appended = true
            // Holes (eyes / gaps) are legitimate but need a smaller span to survive.
            for child in contour.childContours {
                _ = append(child, to: path, minimumSpan: minimumSpan * 0.5)
            }
        }
        return appended
    }

    /// Map Vision normalized path into an AppKit view rect (bottom-leading origin).
    static func pathInView(normalized: CGPath, photoFrame: CGRect) -> CGPath? {
        guard photoFrame.width > 1, photoFrame.height > 1 else { return nil }
        var transform = CGAffineTransform(translationX: photoFrame.minX, y: photoFrame.minY)
            .scaledBy(x: photoFrame.width, y: photoFrame.height)
        return normalized.copy(using: &transform)
    }
}

/// Photo-guided matte tightening for precision Auto Select (accurate path).
enum SelectionMattePrecision {
    /// Snap soft Vision alpha to strong photo edges inside the uncertain boundary band.
    static func refine(mask: CIImage, photo: CIImage, extent: CGRect) -> CIImage {
        let extent = extent.integral
        let photo = photo.cropped(to: extent)
        var matte = mask
        if abs(matte.extent.width - extent.width) > 1 || abs(matte.extent.height - extent.height) > 1 {
            let sx = extent.width / max(matte.extent.width, 1)
            let sy = extent.height / max(matte.extent.height, 1)
            matte = matte.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }
        if matte.extent.origin != extent.origin {
            matte = matte.transformed(
                by: CGAffineTransform(
                    translationX: extent.minX - matte.extent.minX,
                    y: extent.minY - matte.extent.minY
                )
            )
        }
        matte = matte.cropped(to: extent)

        // Scale band with image size so 4K gets a wider search than previews.
        let longEdge = max(extent.width, extent.height)
        let bandRadius = Float(max(2.0, min(10.0, longEdge / 400.0)))

        let luma = photo.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0.0
        ]).cropped(to: extent)
        let edges = luma
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 2.5])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 2.2,
                kCIInputBrightnessKey: 0.05,
                kCIInputSaturationKey: 0.0
            ])
            .cropped(to: extent)

        let clamped = matte.clampedToExtent()
        let dilated = clamped
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: bandRadius])
            .cropped(to: extent)
        let eroded = clamped
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: bandRadius])
            .cropped(to: extent)
        guard let band = CIFilter(name: "CIDifferenceBlendMode", parameters: [
            kCIInputImageKey: dilated,
            kCIInputBackgroundImageKey: eroded
        ])?.outputImage?.cropped(to: extent) else {
            return matte
        }

        // Hard binary matte — preferred where photo edges are strong inside the band.
        let hard = matte
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 20, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 20, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 20, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: -10, y: -10, z: -10, w: 0)
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .cropped(to: extent)

        // snapAmount = band * edges → only boundary pixels with photo structure.
        guard let snapGate = CIFilter(name: "CIMultiplyCompositing", parameters: [
            kCIInputImageKey: band,
            kCIInputBackgroundImageKey: edges
        ])?.outputImage?.cropped(to: extent) else {
            return matte
        }

        // Mix soft Vision matte → hard edge-snapped matte where snapGate is high.
        guard let snapped = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: hard,
            kCIInputBackgroundImageKey: matte,
            kCIInputMaskImageKey: snapGate
        ])?.outputImage?.cropped(to: extent) else {
            return matte
        }

        // Mild contrast recovery so hair/fringe stays soft where edges were weak.
        return snapped
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.15,
                kCIInputBrightnessKey: 0.0,
                kCIInputSaturationKey: 0.0
            ])
            .cropped(to: extent)
    }
}

/// Apple Vision person segmentation — first `SelectionProvider` conformer.
final class VisionPersonSelectionProvider: SelectionProvider, @unchecked Sendable {
    static let id = "vision.person"
    var providerID: String { Self.id }

    /// Long-edge cap for preview working images.
    static let previewMaxEdge: CGFloat = 1280

    private let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()

    func selectClass(
        in image: CIImage,
        class semanticClass: SemanticClass,
        quality: SelectionQuality
    ) async throws -> SelectionMask {
        guard semanticClass == .person else {
            throw SelectionError.unsupportedClass(semanticClass)
        }
        return try await segmentPerson(in: image, quality: quality)
    }

    func selectRegion(
        in image: CIImage,
        at point: CGPoint,
        quality: SelectionQuality
    ) async throws -> SelectionMask {
        let mask = try await segmentPerson(in: image, quality: quality)
        guard pointIsOnPerson(point, mask: mask, imageExtent: image.extent) else {
            throw SelectionError.pointMiss
        }
        return mask
    }

    func select(
        in image: CIImage,
        prompt: SelectionPrompt,
        quality: SelectionQuality
    ) async throws -> SelectionMask {
        if let point = prompt.positivePoints.first {
            return try await selectRegion(in: image, at: point, quality: quality)
        }
        if let box = prompt.box, !box.isNull, !box.isEmpty {
            let center = CGPoint(x: box.midX, y: box.midY)
            return try await selectRegion(in: image, at: center, quality: quality)
        }
        return try await selectClass(in: image, class: .person, quality: quality)
    }

    private func segmentPerson(in image: CIImage, quality: SelectionQuality) async throws -> SelectionMask {
        let extent = image.extent.integral
        guard extent.width > 1, extent.height > 1 else {
            throw SelectionError.invalidImage
        }

        let working: CIImage
        if quality == .preview {
            working = Self.scaledForPreview(image)
        } else {
            // Precision path: full-resolution source, never downscale.
            working = image
        }
        let workingExtent = working.extent.integral

        guard let cgImage = ciContext.createCGImage(working, from: workingExtent) else {
            throw SelectionError.invalidImage
        }

        let maskCG: CGImage = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                    let rawMask: CGImage
                    if quality == .accurate, let instance = self.personInstanceMask(handler: handler) {
                        rawMask = instance
                    } else {
                        rawMask = try self.personSegmentationMask(
                            handler: handler,
                            qualityLevel: quality.visionQualityLevel
                        )
                    }

                    let refined: CGImage
                    if quality == .accurate {
                        let maskCI = CIImage(cgImage: rawMask)
                        let refinedCI = SelectionMattePrecision.refine(
                            mask: maskCI,
                            photo: working,
                            extent: workingExtent
                        )
                        guard let out = self.ciContext.createCGImage(refinedCI, from: workingExtent) else {
                            continuation.resume(throwing: SelectionError.emptyResult)
                            return
                        }
                        refined = out
                    } else {
                        refined = rawMask
                    }

                    if Self.isEffectivelyEmpty(refined) {
                        continuation.resume(throwing: SelectionError.emptyResult)
                        return
                    }
                    continuation.resume(returning: refined)
                } catch let error as SelectionError {
                    continuation.resume(throwing: error)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return SelectionMask(
            cgImage: maskCG,
            extent: workingExtent,
            confidence: quality == .accurate ? 1 : 0.85,
            semanticClass: .person,
            source: .visionPerson
        )
    }

    /// macOS 14+ instance masks are typically crisper than the classic person matte.
    private func personInstanceMask(handler: VNImageRequestHandler) -> CGImage? {
        guard #available(macOS 14.0, *) else { return nil }
        do {
            let request = VNGeneratePersonInstanceMaskRequest()
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            let instances = observation.allInstances
            guard !instances.isEmpty else { return nil }
            let buffer = try observation.generateScaledMaskForImage(
                forInstances: instances,
                from: handler
            )
            let maskCI = CIImage(cvPixelBuffer: buffer)
            let maskExtent = maskCI.extent.integral
            guard let matte = ciContext.createCGImage(maskCI, from: maskExtent) else { return nil }
            if Self.isEffectivelyEmpty(matte) { return nil }
            return matte
        } catch {
            return nil
        }
    }

    private func personSegmentationMask(
        handler: VNImageRequestHandler,
        qualityLevel: VNGeneratePersonSegmentationRequest.QualityLevel
    ) throws -> CGImage {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = qualityLevel
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw SelectionError.emptyResult
        }
        let maskCI = CIImage(cvPixelBuffer: observation.pixelBuffer)
        let maskExtent = maskCI.extent.integral
        guard let matte = ciContext.createCGImage(maskCI, from: maskExtent) else {
            throw SelectionError.emptyResult
        }
        if Self.isEffectivelyEmpty(matte) {
            throw SelectionError.emptyResult
        }
        return matte
    }

    private func pointIsOnPerson(_ point: CGPoint, mask: SelectionMask, imageExtent: CGRect) -> Bool {
        let maskCI = mask.ciImageMatching(extent: imageExtent)
        let px = min(max(point.x, imageExtent.minX), imageExtent.maxX - 1)
        let py = min(max(point.y, imageExtent.minY), imageExtent.maxY - 1)
        let sampleRect = CGRect(x: floor(px), y: floor(py), width: 1, height: 1)
        var pixel: [UInt8] = [0, 0, 0, 0]
        ciContext.render(
            maskCI,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: sampleRect,
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        // Mattes from Vision often become opaque RGBA (RGB = luma, A = 255). Ignore alpha —
        // otherwise empty (0,0,0,255) regions always count as hits.
        return max(pixel[0], pixel[1], pixel[2]) > 32
    }

    static func scaledForPreview(_ image: CIImage) -> CIImage {
        let extent = image.extent
        let longest = max(extent.width, extent.height)
        guard longest > previewMaxEdge else { return image }
        let scale = previewMaxEdge / longest
        var scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        if scaled.extent.origin != .zero {
            scaled = scaled.transformed(
                by: CGAffineTransform(translationX: -scaled.extent.minX, y: -scaled.extent.minY)
            )
        }
        return scaled
    }

    /// Reject Vision noise / document false-positives. Real subjects (even full-body)
    /// typically cover well above this; sparse speckles stay under it.
    static let minimumPersonCoverage: Double = 0.08

    private static func isEffectivelyEmpty(_ image: CGImage) -> Bool {
        // Sample up to 128×128 so sparse noise and weak false mattes are visible.
        let width = min(image.width, 128)
        let height = min(image.height, 128)
        guard width > 0, height > 0 else { return true }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return true }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return true }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        var maxValue: UInt8 = 0
        var on = 0
        var sum = 0
        let count = width * height
        for i in 0..<count {
            let v = buffer[i]
            maxValue = max(maxValue, v)
            sum += Int(v)
            if v > 32 { on += 1 }
        }
        let coverage = Double(on) / Double(count)
        let mean = Double(sum) / Double(count)
        // Strong empty signals: no bright pixels, or coverage under the subject floor.
        if maxValue <= 40 { return true }
        if coverage < minimumPersonCoverage { return true }
        // Ultra-dim mats with weak mean are document / texture ghosts.
        if mean < 8 && coverage < 0.12 { return true }
        return false
    }
}

private extension SelectionQuality {
    var visionQualityLevel: VNGeneratePersonSegmentationRequest.QualityLevel {
        switch self {
        case .preview: return .balanced
        case .accurate: return .accurate
        }
    }
}
