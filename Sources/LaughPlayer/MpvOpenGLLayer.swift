import AppKit
import OpenGL
import QuartzCore

/// Hosts mpv's OpenGL renderer inside LaughPlayer. libmpv draws here so cocoa-cb never opens a second window.
///
/// OpenGL is deprecated on macOS; libmpv's public render API is still GL, so this layer is required.
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

final class MpvRenderHostView: NSView {
    let renderLayer = MpvOpenGLLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = renderLayer
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        renderLayer.frame = bounds
        renderLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { true }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        renderLayer.contentsScale = window?.backingScaleFactor ?? 2
        renderLayer.setNeedsDisplay()
    }

    override func layout() {
        super.layout()
        renderLayer.frame = bounds
        renderLayer.setNeedsDisplay()
    }

    override func scrollWheel(with event: NSEvent) {
        // Forward to PlayerSurfaceView so volume/seek scroll works over mpv embeds.
        superview?.scrollWheel(with: event)
    }
}
