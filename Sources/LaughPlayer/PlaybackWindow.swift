import AppKit

/// Main window — enforces locked aspect ratio during live resize via `constrainFrameRect`.
final class PlaybackWindow: NSWindow {
    var aspectLockRatio: CGFloat?
    private var isConstrainingFrame = false

    private static let lockedContentMinWidth: CGFloat = 480
    private static let lockedContentMinHeight: CGFloat = 240

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        if isConstrainingFrame {
            return frameRect
        }
        isConstrainingFrame = true
        defer { isConstrainingFrame = false }

        let constrained = super.constrainFrameRect(frameRect, to: screen)
        guard let ratio = aspectLockRatio, ratio > 0, !styleMask.contains(.fullScreen) else {
            return constrained
        }
        return Self.snapFrameToAspect(
            proposedFrame: constrained,
            currentFrame: frame,
            ratio: ratio,
            window: self
        )
    }

    static func minimumContentSize(forAspectRatio ratio: CGFloat) -> NSSize {
        var width = lockedContentMinWidth
        var height = ceil(width / ratio)
        if height < lockedContentMinHeight {
            height = lockedContentMinHeight
            width = ceil(height * ratio)
        }
        return NSSize(width: width, height: height)
    }

    static func snapFrameToAspect(
        proposedFrame: NSRect,
        currentFrame: NSRect,
        ratio: CGFloat,
        window: NSWindow
    ) -> NSRect {
        let widthDelta = abs(proposedFrame.width - currentFrame.width)
        let heightDelta = abs(proposedFrame.height - currentFrame.height)

        var contentRect = window.contentRect(forFrameRect: proposedFrame)
        if widthDelta >= heightDelta {
            contentRect.size.height = contentRect.width / ratio
        } else {
            contentRect.size.width = contentRect.height * ratio
        }

        let contentMin = minimumContentSize(forAspectRatio: ratio)
        if contentRect.width < contentMin.width {
            contentRect.size.width = contentMin.width
            contentRect.size.height = contentMin.width / ratio
        }
        if contentRect.height < contentMin.height {
            contentRect.size.height = contentMin.height
            contentRect.size.width = contentMin.height * ratio
        }

        var snappedFrame = window.frameRect(forContentRect: contentRect)
        guard snappedFrame.width.isFinite, snappedFrame.height.isFinite,
              snappedFrame.width > 0, snappedFrame.height > 0 else {
            return proposedFrame
        }
        snappedFrame.origin.x = proposedFrame.origin.x + (proposedFrame.width - snappedFrame.width)
        snappedFrame.origin.y = proposedFrame.origin.y + (proposedFrame.height - snappedFrame.height)
        return snappedFrame
    }
}
