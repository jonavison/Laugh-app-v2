import AppKit

/// Compact five-point tone curve editor for Edits → Curves.
final class ImageToneCurveEditorView: NSView {
    var onCurveChange: (([Double]) -> Void)?

    private var points: [Double] = ImageAdjustParameters.identityCurve
    private var dragIndex: Int?

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 140) }
    /// Immersive windows are movable by background — never drag the frame from the curve.
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCurve(_ curve: [Double]) {
        points = ImageAdjustParameters.identityCurve
        let normalized = curve.count >= 5 ? Array(curve.prefix(5)) : curve
        for (i, v) in normalized.enumerated() where i < 5 {
            points[i] = max(0, min(1, v))
        }
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds.insetBy(dx: 8, dy: 8)
        LaughTheme.imageStudioFloorColor(appearance: effectiveAppearance)
            .withAlphaComponent(0.35)
            .setFill()
        bounds.fill()

        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        let grid = NSBezierPath()
        grid.lineWidth = 1
        for i in 1..<4 {
            let x = bounds.minX + bounds.width * CGFloat(i) / 4
            let y = bounds.minY + bounds.height * CGFloat(i) / 4
            grid.move(to: NSPoint(x: x, y: bounds.minY))
            grid.line(to: NSPoint(x: x, y: bounds.maxY))
            grid.move(to: NSPoint(x: bounds.minX, y: y))
            grid.line(to: NSPoint(x: bounds.maxX, y: y))
        }
        grid.stroke()

        // Identity diagonal
        NSColor.tertiaryLabelColor.setStroke()
        let diag = NSBezierPath()
        diag.lineWidth = 1
        diag.move(to: NSPoint(x: bounds.minX, y: bounds.maxY))
        diag.line(to: NSPoint(x: bounds.maxX, y: bounds.minY))
        diag.stroke()

        let path = NSBezierPath()
        path.lineWidth = 1.75
        for i in 0..<5 {
            let p = pointInBounds(index: i, bounds: bounds)
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        LaughTheme.interactiveAccent.setStroke()
        path.stroke()

        for i in 0..<5 {
            let p = pointInBounds(index: i, bounds: bounds)
            let r: CGFloat = i == dragIndex ? 5.5 : 4.5
            let knob = NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            NSColor.labelColor.setFill()
            knob.fill()
            LaughTheme.interactiveAccent.setStroke()
            knob.lineWidth = 1.25
            knob.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let loc = convert(event.locationInWindow, from: nil)
        let bounds = self.bounds.insetBy(dx: 8, dy: 8)
        let nearest = (0..<5).min(by: {
            hypot(pointInBounds(index: $0, bounds: bounds).x - loc.x,
                  pointInBounds(index: $0, bounds: bounds).y - loc.y)
                < hypot(pointInBounds(index: $1, bounds: bounds).x - loc.x,
                        pointInBounds(index: $1, bounds: bounds).y - loc.y)
        })
        // Prefer nearby knobs; otherwise pick the column under the click so a
        // miss on empty plot still edits instead of starting a window drag.
        if let nearest {
            let p = pointInBounds(index: nearest, bounds: bounds)
            if hypot(p.x - loc.x, p.y - loc.y) <= 18 {
                dragIndex = nearest
            } else if bounds.contains(loc) {
                let t = max(0, min(1, (loc.x - bounds.minX) / max(bounds.width, 1)))
                dragIndex = min(4, max(0, Int((t * 4).rounded())))
            } else {
                dragIndex = nil
            }
        }
        updateDrag(loc)
    }

    override func mouseDragged(with event: NSEvent) {
        updateDrag(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        dragIndex = nil
        needsDisplay = true
    }

    private func updateDrag(_ loc: NSPoint) {
        guard let dragIndex else { return }
        let bounds = self.bounds.insetBy(dx: 8, dy: 8)
        let y = max(0, min(1, 1 - Double((loc.y - bounds.minY) / max(bounds.height, 1))))
        points[dragIndex] = y
        // Keep endpoints editable but clamp neighbors softly for a usable curve.
        if dragIndex > 0 { points[dragIndex] = max(points[dragIndex], points[dragIndex - 1] - 0.35) }
        if dragIndex < 4 { points[dragIndex] = min(points[dragIndex], points[dragIndex + 1] + 0.35) }
        onCurveChange?(points)
        needsDisplay = true
    }

    private func pointInBounds(index: Int, bounds: NSRect) -> NSPoint {
        let xs: [CGFloat] = [0, 0.25, 0.5, 0.75, 1]
        let x = bounds.minX + bounds.width * xs[index]
        let y = bounds.maxY - bounds.height * CGFloat(points[index])
        return NSPoint(x: x, y: y)
    }
}
