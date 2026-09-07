import CoreImage
import Foundation

/// Local matte brush modes (Select and Mask–style). Class-blind — operates on alpha only.
enum SelectionBrushMode: String, Sendable, Hashable, CaseIterable {
    /// Expand selection under the stamp.
    case paintIn
    /// Contract selection under the stamp.
    case paintOut
    /// Re-snap matte to photo edges inside the stamp (local precision polish).
    case refineEdge

    var menuTitle: String {
        switch self {
        case .paintIn: return "Paint In"
        case .paintOut: return "Paint Out"
        case .refineEdge: return "Refine Edge"
        }
    }
}

/// Soft circular stamp + paint / refine-edge ops for `SelectionMask` alpha.
enum SelectionBrushEngine {
    /// Soft disk in image pixel space (white center → transparent edge).
    static func softStamp(center: CGPoint, radius: CGFloat, extent: CGRect) -> CIImage {
        let r = max(1, radius)
        let soft = max(1, r * 0.35)
        guard let filter = CIFilter(name: "CIRadialGradient") else {
            return CIImage(color: .white).cropped(
                to: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            ).cropped(to: extent)
        }
        filter.setValue(CIVector(x: center.x, y: center.y), forKey: "inputCenter")
        filter.setValue(max(0, r - soft) as NSNumber, forKey: "inputRadius0")
        filter.setValue(r as NSNumber, forKey: "inputRadius1")
        filter.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor0")
        filter.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 0), forKey: "inputColor1")
        let stamp = (filter.outputImage ?? CIImage(color: .white))
            .cropped(to: CGRect(x: center.x - r - 1, y: center.y - r - 1, width: (r + 1) * 2, height: (r + 1) * 2))
        return stamp.cropped(to: extent)
    }

    /// Applies one brush tap. `photo` required for `.refineEdge`.
    static func apply(
        mask: CIImage,
        photo: CIImage?,
        mode: SelectionBrushMode,
        center: CGPoint,
        radius: CGFloat,
        extent: CGRect
    ) -> CIImage {
        let extent = extent.integral
        let current = mask.cropped(to: extent)
        let stamp = softStamp(center: center, radius: radius, extent: extent)

        switch mode {
        case .paintIn:
            guard let out = CIFilter(name: "CIMaximumCompositing", parameters: [
                kCIInputImageKey: current,
                kCIInputBackgroundImageKey: stamp
            ])?.outputImage else {
                return current
            }
            return out.cropped(to: extent)

        case .paintOut:
            // Invert stamp → multiply with matte.
            let inverted = stamp
                .applyingFilter("CIColorInvert")
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.0
                ])
            guard let out = CIFilter(name: "CIMultiplyCompositing", parameters: [
                kCIInputImageKey: current,
                kCIInputBackgroundImageKey: inverted
            ])?.outputImage else {
                return current
            }
            return out.cropped(to: extent)

        case .refineEdge:
            guard let photo else { return current }
            let polished = SelectionMattePrecision.refine(mask: current, photo: photo, extent: extent)
            // Mix polished only under the stamp; leave outside untouched.
            guard let mixed = CIFilter(name: "CIBlendWithMask", parameters: [
                kCIInputImageKey: polished,
                kCIInputBackgroundImageKey: current,
                kCIInputMaskImageKey: stamp
            ])?.outputImage else {
                return current
            }
            return mixed.cropped(to: extent)
        }
    }
}

/// Fringe color spill reduction for cutouts (class-blind). Amount 0…1.
enum SelectionDecontaminate {
    /// Desaturates and pulls fringe pixels toward interior subject luminance under the edge band.
    static func apply(
        image: CIImage,
        mask: CIImage,
        amount: Double,
        extent: CGRect
    ) -> CIImage {
        let amount = min(1, max(0, amount))
        guard amount > 0.0005 else { return image.cropped(to: extent) }
        let extent = extent.integral
        let photo = image.cropped(to: extent)
        let matte = mask.cropped(to: extent)

        let bandRadius = Float(max(1.5, min(8, max(extent.width, extent.height) / 500.0)) * (0.5 + amount))
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
            return photo
        }

        // Desaturated / slightly darkened fringe candidate.
        let cleaned = photo.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: max(0, 1.0 - amount * 0.95),
            kCIInputBrightnessKey: -0.02 * amount,
            kCIInputContrastKey: 1.0
        ]).cropped(to: extent)

        // Gate: only replace inside the edge band, scaled by amount.
        let gate = band.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: amount, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: amount, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ]).cropped(to: extent)

        guard let mixed = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: cleaned,
            kCIInputBackgroundImageKey: photo,
            kCIInputMaskImageKey: gate
        ])?.outputImage else {
            return photo
        }
        return mixed.cropped(to: extent)
    }
}
