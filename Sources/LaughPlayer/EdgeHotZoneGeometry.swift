import CoreGraphics

/// Geometry for side-panel edge clicks vs window-resize grips.
enum EdgeHotZoneGeometry {
    /// Full strip considered for panel open/close (from the window / sheet edge).
    static let width: CGFloat = 42
    /// Outer rim reserved for AppKit resize — never arms a panel action here.
    static let windowResizeRim: CGFloat = 6
    /// Keep top/bottom corners free for corner resize grips.
    static let cornerExclusion: CGFloat = 12
    /// Max movement (points²) between down/up still counts as a click, not a drag.
    static let clickSlopSquared: CGFloat = 16 // 4pt

    static func isInWindowResizeRim(point: CGPoint, bounds: CGRect) -> Bool {
        point.x <= windowResizeRim
            || point.x >= bounds.width - windowResizeRim
            || point.y <= windowResizeRim
            || point.y >= bounds.height - windowResizeRim
    }

    /// Inner band only — past the resize rim, clear of corners.
    static func isInLeftOpenZone(point: CGPoint, bounds: CGRect) -> Bool {
        guard bounds.width > width * 2 else { return false }
        guard point.x > windowResizeRim, point.x <= width else { return false }
        return isClearOfVerticalResizeRim(point.y, height: bounds.height)
    }

    static func isInRightOpenZone(point: CGPoint, bounds: CGRect) -> Bool {
        guard bounds.width > width * 2 else { return false }
        let minX = bounds.width - width
        let maxX = bounds.width - windowResizeRim
        guard point.x >= minX, point.x < maxX else { return false }
        return isClearOfVerticalResizeRim(point.y, height: bounds.height)
    }

    /// Interior strip just leading the open settings sheet (not a window-edge resize conflict).
    static func isInRightCloseZone(point: CGPoint, bounds: CGRect, sheetLeadingX: CGFloat) -> Bool {
        guard bounds.width > width else { return false }
        guard point.x >= (sheetLeadingX - width), point.x < sheetLeadingX else { return false }
        return isClearOfVerticalResizeRim(point.y, height: bounds.height)
    }

    static func isClickNotDrag(from start: CGPoint, to end: CGPoint) -> Bool {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return (dx * dx + dy * dy) <= clickSlopSquared
    }

    private static func isClearOfVerticalResizeRim(_ y: CGFloat, height: CGFloat) -> Bool {
        y > cornerExclusion && y < (height - cornerExclusion)
    }
}
