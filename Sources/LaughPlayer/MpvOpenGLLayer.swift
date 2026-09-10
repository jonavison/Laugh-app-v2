import AppKit
import CoreGraphics
import OpenGL
import QuartzCore

/// Hosts mpv's OpenGL renderer inside LaughPlayer. Kept for experiments; picture defaults to software blit.
///
/// OpenGL is deprecated on macOS; libmpv's GL render API currently presents black video here.
final class MpvOpenGLLayer: CAOpenGLLayer {
    var onDraw: ((_ fbo: Int32, _ width: Int32, _ height: Int32) -> Void)?
    var onContextReady: (() -> Void)?

    private var didSignalContextReady = false

    override init() {
        super.init()
        isOpaque = true
        isAsynchronous = false
        needsDisplayOnBoundsChange = true
        contentsGravity = .resize
        backgroundColor = NSColor.black.cgColor
        autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        let attributes: [CGLPixelFormatAttribute] = [
            kCGLPFAOpenGLProfile,
            CGLPixelFormatAttribute(rawValue: UInt32(kCGLOGLPVersion_3_2_Core.rawValue)),
            kCGLPFAAccelerated,
            kCGLPFADoubleBuffer,
            CGLPixelFormatAttribute(rawValue: 0)
        ]
        var pixelFormat: CGLPixelFormatObj?
        var count: GLint = 0
        let error = attributes.withUnsafeBufferPointer { buffer -> CGLError in
            guard let base = buffer.baseAddress else { return CGLError(rawValue: 1) }
            return CGLChoosePixelFormat(base, &pixelFormat, &count)
        }
        if error == kCGLNoError, let pixelFormat {
            return pixelFormat
        }
        return super.copyCGLPixelFormat(forDisplayMask: mask)
    }

    override func draw(
        inCGLContext context: CGLContextObj,
        pixelFormat: CGLPixelFormatObj,
        forLayerTime t: CFTimeInterval,
        displayTime ts: UnsafePointer<CVTimeStamp>?
    ) {
        CGLSetCurrentContext(context)
        if !didSignalContextReady {
            didSignalContextReady = true
            onContextReady?()
        }
        let scale = max(contentsScale, 1)
        let width = Int32((bounds.width * scale).rounded())
        let height = Int32((bounds.height * scale).rounded())
        guard width > 0, height > 0 else { return }
        onDraw?(0, width, height)
    }
}

/// CPU blit surface for `MPV_RENDER_API_TYPE_SW`. Renders into a BGRA buffer and shows it in a CALayer.
final class MpvSoftwareBlitView: NSView {
    /// Cap long edge so SW present leaves CPU for CoreAudio (4K blit was starving audio).
    static let maxLongEdgePixels: CGFloat = 1280
    /// Soft cap ~24fps blit; mpv still decodes full rate for audio sync.
    static let minBlitIntervalSec: CFTimeInterval = 1.0 / 24.0

    var onRenderFrame: ((_ width: Int32, _ height: Int32, _ stride: Int, _ pixels: UnsafeMutableRawPointer) -> Bool)?
    /// When true, treat near-black pixels as transparent so this view can sit over AVPlayer.
    var keysBlackBackgroundToAlpha = false
    /// Override long-edge cap (overlay-only path can afford more pixels — no video decode).
    var maxLongEdgeOverride: CGFloat?
    /// Override blit cadence (overlay uses a lower rate to keep UI responsive).
    var minBlitIntervalOverride: CFTimeInterval?
    /// When set, SW render + black-key run here; `layer.contents` updates on main.
    var asyncRenderQueue: DispatchQueue?

    private let imageLayer = CALayer()
    private var pixelBuffer: UnsafeMutableRawPointer?
    private var pixelCapacity = 0
    private var lastPixelWidth = 0
    private var lastPixelHeight = 0
    private var lastBlitWallTime: CFAbsoluteTime = 0
    private var asyncRenderGeneration: UInt64 = 0
    private var asyncBlitInFlight = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        imageLayer.contentsGravity = .resize
        imageLayer.backgroundColor = NSColor.black.cgColor
        imageLayer.frame = bounds
        imageLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer = imageLayer
    }

    func configureAsTransparentOverlay() {
        keysBlackBackgroundToAlpha = true
        maxLongEdgeOverride = 960
        minBlitIntervalOverride = 1.0 / 12.0
        asyncRenderQueue = DispatchQueue(label: "laugh.bitmap-overlay.blit", qos: .userInitiated)
        imageLayer.backgroundColor = NSColor.clear.cgColor
        imageLayer.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        pixelBuffer?.deallocate()
    }

    override var isOpaque: Bool { !keysBlackBackgroundToAlpha }

    override func hitTest(_ point: NSPoint) -> NSView? {
        keysBlackBackgroundToAlpha ? nil : super.hitTest(point)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        requestFrame()
    }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
        requestFrame()
    }

    func requestFrame() {
        let interval = minBlitIntervalOverride ?? Self.minBlitIntervalSec
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastBlitWallTime < interval, imageLayer.contents != nil {
            return
        }
        lastBlitWallTime = now

        if let queue = asyncRenderQueue {
            requestFrameAsync(on: queue)
        } else {
            renderIntoLayer()
        }
    }

    private func requestFrameAsync(on queue: DispatchQueue) {
        if asyncBlitInFlight { return }
        asyncBlitInFlight = true
        asyncRenderGeneration &+= 1
        let generation = asyncRenderGeneration
        let size = renderSize()
        let stride = size.width * 4
        let bytes = stride * size.height
        let keyAlpha = keysBlackBackgroundToAlpha
        let render = onRenderFrame

        queue.async { [weak self] in
            defer {
                DispatchQueue.main.async { self?.asyncBlitInFlight = false }
            }
            guard let render else { return }
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 64)
            defer { buffer.deallocate() }
            memset(buffer, 0, bytes)
            let ok = render(Int32(size.width), Int32(size.height), stride, buffer)
            guard ok else { return }
            if keyAlpha {
                Self.applyBlackKeyAlphaStatic(
                    pixels: buffer,
                    width: size.width,
                    height: size.height,
                    stride: stride
                )
            }
            let copy = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 64)
            copy.copyMemory(from: buffer, byteCount: bytes)
            let provider = CGDataProvider(
                dataInfo: copy,
                data: copy,
                size: bytes,
                releaseData: { info, _, _ in info?.deallocate() }
            )
            guard let provider else {
                copy.deallocate()
                return
            }
            let alphaInfo: CGImageAlphaInfo = keyAlpha ? .premultipliedFirst : .noneSkipFirst
            guard let image = CGImage(
                width: size.width,
                height: size.height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: stride,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: alphaInfo.rawValue)),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            ) else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.asyncRenderGeneration else { return }
                self.imageLayer.contents = image
                self.lastPixelWidth = size.width
                self.lastPixelHeight = size.height
            }
        }
    }

    private func renderSize() -> (width: Int, height: Int) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        // Overlay keys glyphs — Retina full-res blit is wasted CPU; cap backing scale.
        let effectiveScale = asyncRenderQueue == nil ? scale : min(scale, 1.5)
        var width = max(1, Int((bounds.width * effectiveScale).rounded()))
        var height = max(1, Int((bounds.height * effectiveScale).rounded()))
        let longEdge = CGFloat(max(width, height))
        let cap = maxLongEdgeOverride ?? Self.maxLongEdgePixels
        if longEdge > cap {
            let factor = cap / longEdge
            width = max(1, Int((CGFloat(width) * factor).rounded()))
            height = max(1, Int((CGFloat(height) * factor).rounded()))
        }
        // Keep even dimensions for chroma-friendly scaling.
        width -= width % 2
        height -= height % 2
        return (max(2, width), max(2, height))
    }

    private func renderIntoLayer() {
        guard let onRenderFrame else { return }
        let size = renderSize()
        let stride = size.width * 4
        let bytes = stride * size.height
        if pixelCapacity < bytes {
            pixelBuffer?.deallocate()
            pixelBuffer = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 64)
            pixelCapacity = bytes
        }
        guard let pixelBuffer else { return }
        memset(pixelBuffer, 0, bytes)
        let ok = onRenderFrame(Int32(size.width), Int32(size.height), stride, pixelBuffer)
        guard ok else { return }

        if keysBlackBackgroundToAlpha {
            applyBlackKeyAlpha(pixels: pixelBuffer, width: size.width, height: size.height, stride: stride)
        }

        // Copy so CALayer can retain the image while we overwrite the scratch buffer next frame.
        let copy = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 64)
        copy.copyMemory(from: pixelBuffer, byteCount: bytes)
        let provider = CGDataProvider(
            dataInfo: copy,
            data: copy,
            size: bytes,
            releaseData: { info, _, _ in info?.deallocate() }
        )
        guard let provider else {
            copy.deallocate()
            return
        }

        let alphaInfo: CGImageAlphaInfo = keysBlackBackgroundToAlpha
            ? .premultipliedFirst
            : .noneSkipFirst
        guard let image = CGImage(
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: stride,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: alphaInfo.rawValue)),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return }

        imageLayer.contents = image
        lastPixelWidth = size.width
        lastPixelHeight = size.height
    }

    /// Near-black → transparent; brighter pixels keep luminance as alpha (soft glyph edges).
    private func applyBlackKeyAlpha(
        pixels: UnsafeMutableRawPointer,
        width: Int,
        height: Int,
        stride: Int
    ) {
        Self.applyBlackKeyAlphaStatic(pixels: pixels, width: width, height: height, stride: stride)
    }

    private static func applyBlackKeyAlphaStatic(
        pixels: UnsafeMutableRawPointer,
        width: Int,
        height: Int,
        stride: Int
    ) {
        let threshold = 18
        for y in 0..<height {
            let row = pixels.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let i = x * 4
                let b = Int(row[i])
                let g = Int(row[i + 1])
                let r = Int(row[i + 2])
                let lum = (r + g + b) / 3
                if lum <= threshold {
                    row[i] = 0
                    row[i + 1] = 0
                    row[i + 2] = 0
                    row[i + 3] = 0
                } else {
                    let a = min(255, lum + 40)
                    row[i] = UInt8(b * a / 255)
                    row[i + 1] = UInt8(g * a / 255)
                    row[i + 2] = UInt8(r * a / 255)
                    row[i + 3] = UInt8(a)
                }
            }
        }
    }
}

final class MpvRenderHostView: NSView {
    let openGLLayer = MpvOpenGLLayer()
    let softwareBlitView = MpvSoftwareBlitView()

    /// Active present surface for DirectMpv picture.
    var presentCapability: MpvPresentCapability = MpvPresentCapability.preferred {
        didSet { applyPresentMode() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        softwareBlitView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(softwareBlitView)
        NSLayoutConstraint.activate([
            softwareBlitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            softwareBlitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            softwareBlitView.topAnchor.constraint(equalTo: topAnchor),
            softwareBlitView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // OpenGL layer kept offscreen / unused unless experiments re-enable it.
        openGLLayer.frame = bounds
        openGLLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        applyPresentMode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { true }

    var renderLayer: MpvOpenGLLayer { openGLLayer }

    func requestPresentRefresh() {
        switch presentCapability {
        case .softwareBlit:
            softwareBlitView.requestFrame()
        case .openGLDeprecated, .metalUnavailable:
            openGLLayer.setNeedsDisplay()
        }
    }

    private func applyPresentMode() {
        let useSW = presentCapability == .softwareBlit
        softwareBlitView.isHidden = !useSW
        if useSW {
            layer = nil
            wantsLayer = true
        }
    }

    override func scrollWheel(with event: NSEvent) {
        superview?.scrollWheel(with: event)
    }
}
