import AppKit

/// Thin, low-contrast overlay scroller for the edit column.
final class SoftThinScroller: NSScroller {
    private static let knobWidth: CGFloat = 3.5
    private static let knobInset: CGFloat = 2.5

    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        knobWidth + knobInset * 2
    }

    override func draw(_ dirtyRect: NSRect) {
        // Transparent track — only the soft knob.
        drawKnob()
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // No slot fill / rail.
    }

    override func drawKnob() {
        var knob = rect(for: .knob)
        guard knob.width > 0.5, knob.height > 0.5 else { return }

        if usableParts == .noScrollerParts { return }

        let isVertical = bounds.width < bounds.height
        if isVertical {
            let width = Self.knobWidth
            knob.origin.x = bounds.maxX - width - Self.knobInset
            knob.size.width = width
            knob = knob.insetBy(dx: 0, dy: 1)
        } else {
            let height = Self.knobWidth
            knob.origin.y = bounds.maxY - height - Self.knobInset
            knob.size.height = height
            knob = knob.insetBy(dx: 1, dy: 0)
        }

        let radius = min(knob.width, knob.height) / 2
        let path = NSBezierPath(roundedRect: knob, xRadius: radius, yRadius: radius)
        knobFillColor.setFill()
        path.fill()
    }

    private var knobFillColor: NSColor {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Soft grey — intentionally quieter than the system overlay knob.
        if isDark {
            return NSColor.white.withAlphaComponent(alphaValue * 0.22)
        }
        return NSColor.black.withAlphaComponent(alphaValue * 0.18)
    }
}
