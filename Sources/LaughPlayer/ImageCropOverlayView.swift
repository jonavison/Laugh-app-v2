import AppKit

/// Interactive crop rectangle over the fitted photo (normalized coords, bottom-leading).
/// Drag handles to resize/move; drag the dimmed (discarded) area to straighten angle.
final class ImageCropOverlayView: NSView {
    var onDraftChanged: ((CGRect) -> Void)?
    var onStraightenChanged: ((CGFloat) -> Void)?
    var onStraightenDragEnded: (() -> Void)?
    /// Double-click inside the crop rectangle.
    var onApplyRequested: (() -> Void)?

    private(set) var draftNormalized = ImageCropGeometry.fullNormalized
    private(set) var straightenRadians: CGFloat = 0
    private var aspect: ImageCropAspect = .free
    /// Post-straighten AABB size (normalized crop space).
    private var imageSize: CGSize = .zero
    /// Oriented size before straighten — used to keep crop on opaque pixels.
    private var preStraightenSize: CGSize = .zero
    /// Frame of the photo inside this overlay’s bounds (view coords, bottom-leading if non-flipped).
    private var imageFrameInOverlay: CGRect = .zero
    /// Extra margin around the photo for straighten gestures (outside the cropable image).
    private static let toolingPad: CGFloat = 52

    private enum DragKind {
        case handle(ImageCropHandle)
        case straighten
    }

    private var activeDrag: DragKind?
    private var straightenDragStartPointerAngle: CGFloat = 0
    private var straightenDragStartRadians: CGFloat = 0
    private var trackingArea: NSTrackingArea?
    /// Latest pointer in overlay coords (for angle badge placement).
    private var pointerInOverlay: CGPoint?

    /// Generous hit target so handles are easy to grab.
    private let handleHitSlop: CGFloat = 16
    private let handleVisualSize: CGFloat = 11
    /// Soft dim over discarded photo only (pad stays true studio floor).
    private let outsideCropDim = NSColor.labelColor.withAlphaComponent(0.22)
    private let badgeCursorOffset = CGPoint(x: 14, y: 14)

    /// Quantized orbit cursors (move-3d icon rotated around the crop).
    private var rotateCursorCache: [Int: NSCursor] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { false }

    /// Transparent crop chrome must not initiate window drags (full-size titlebar apps).
    override var mouseDownCanMoveWindow: Bool { false }

    func configure(
        draftNormalized: CGRect,
        aspect: ImageCropAspect,
        imageSize: CGSize,
        preStraightenSize: CGSize,
        imageFrameInOverlay: CGRect,
        straightenRadians: CGFloat
    ) {
        self.aspect = aspect
        self.imageSize = imageSize
        self.preStraightenSize = preStraightenSize
        self.imageFrameInOverlay = imageFrameInOverlay
        self.straightenRadians = ImageCropGeometry.clampStraightenRadians(straightenRadians)
        self.draftNormalized = clampedDraft(draftNormalized)
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func setAspect(_ aspect: ImageCropAspect) {
        self.aspect = aspect
        draftNormalized = clampedDraft(
            ImageCropGeometry.applyAspect(aspect, to: draftNormalized, imageSize: imageSize)
        )
        onDraftChanged?(draftNormalized)
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func setStraightenRadians(_ radians: CGFloat) {
        straightenRadians = ImageCropGeometry.clampStraightenRadians(radians)
        draftNormalized = clampedDraft(draftNormalized)
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func clampedDraft(_ rect: CGRect) -> CGRect {
        let pre = preStraightenSize.width > 1 ? preStraightenSize : imageSize
        var next = ImageCropGeometry.clampToOpaqueContent(
            ImageCropGeometry.sanitized(rect),
            straightenRadians: straightenRadians,
            preStraightenSize: pre
        )
        // Hard clamp in view space so the frame can never paint outside the photo.
        next = clampNormalizedToImageFrame(next)
        return ImageCropGeometry.clampToOpaqueContent(
            next,
            straightenRadians: straightenRadians,
            preStraightenSize: pre
        )
    }

    /// Guarantee crop ⊆ photo frame in overlay coordinates, then map back to normalized.
    private func clampNormalizedToImageFrame(_ rect: CGRect) -> CGRect {
        let f = imageFrameInOverlay
        guard f.width > 1, f.height > 1 else { return ImageCropGeometry.sanitized(rect) }
        let n = ImageCropGeometry.sanitized(rect)
        var view = CGRect(
            x: f.minX + n.minX * f.width,
            y: f.minY + n.minY * f.height,
            width: n.width * f.width,
            height: n.height * f.height
        ).standardized
        let minEdge = max(8, ImageCropGeometry.minNormalizedEdge * min(f.width, f.height))
        view.size.width = min(max(view.width, minEdge), f.width)
        view.size.height = min(max(view.height, minEdge), f.height)
        view.origin.x = min(max(view.origin.x, f.minX), f.maxX - view.width)
        view.origin.y = min(max(view.origin.y, f.minY), f.maxY - view.height)
        return ImageCropGeometry.sanitized(
            CGRect(
                x: (view.minX - f.minX) / f.width,
                y: (view.minY - f.minY) / f.height,
                width: view.width / f.width,
                height: view.height / f.height
            )
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .mouseMoved,
            .mouseEnteredAndExited,
            .cursorUpdate,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        guard !isHidden else { return }
        let crop = cropViewRect()
        let tooling = toolingFrameInOverlay()

        // Straighten zone = tooling pad (around + discarded photo), not the crop interior.
        if tooling.width > 1, tooling.height > 1 {
            addCursorRect(tooling, cursor: rotateCursor(at: pointerInOverlay))
        }
        addCursorRect(crop.insetBy(dx: handleHitSlop, dy: handleHitSlop), cursor: .openHand)

        for (handle, loc) in handlePoints(in: crop) {
            let r = CGRect(
                x: loc.x - handleHitSlop,
                y: loc.y - handleHitSlop,
                width: handleHitSlop * 2,
                height: handleHitSlop * 2
            )
            addCursorRect(r, cursor: cursor(for: handle, dragging: false))
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        pointerInOverlay = p
        if let drag = activeDrag {
            switch drag {
            case .handle(let handle):
                cursor(for: handle, dragging: true).set()
            case .straighten:
                rotateCursor(at: p).set()
            }
            return
        }
        if let handle = hitTestHandle(at: p) {
            cursor(for: handle, dragging: false).set()
        } else if cropViewRect().insetBy(dx: handleHitSlop, dy: handleHitSlop).contains(p) {
            NSCursor.openHand.set()
        } else if isInStraightenZone(p) {
            rotateCursor(at: p).set()
            needsDisplay = true
        } else {
            NSCursor.arrow.set()
            needsDisplay = true
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        pointerInOverlay = p

        // Double-click inside the kept region commits the crop (same as Apply).
        if event.clickCount >= 2, cropViewRect().contains(p) {
            activeDrag = nil
            onApplyRequested?()
            return
        }

        if let handle = hitTestHandle(at: p) {
            activeDrag = .handle(handle)
            cursor(for: handle, dragging: true).set()
            guard let normalized = viewPointToNormalized(p) else { return }
            if handle != .move {
                draftNormalized = clampedDraft(
                    ImageCropGeometry.resize(
                        rect: draftNormalized,
                        handle: handle,
                        to: normalized,
                        aspectRatio: aspect.lockedRatio(imageSize: imageSize)
                    )
                )
                onDraftChanged?(draftNormalized)
                needsDisplay = true
            }
            return
        }

        if cropViewRect().contains(p) {
            activeDrag = .handle(.move)
            NSCursor.closedHand.set()
            return
        }

        // Tooling pad / discarded photo → free straighten angle (never the crop interior).
        if isInStraightenZone(p) {
            activeDrag = .straighten
            let center = CGPoint(x: cropViewRect().midX, y: cropViewRect().midY)
            straightenDragStartPointerAngle = atan2(p.y - center.y, p.x - center.x)
            straightenDragStartRadians = straightenRadians
            rotateCursor(at: p).set()
            needsDisplay = true
            return
        }

        activeDrag = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag = activeDrag else { return }
        let p = convert(event.locationInWindow, from: nil)
        pointerInOverlay = p

        switch drag {
        case .handle(let handle):
            guard let normalized = viewPointToNormalized(p) else { return }
            draftNormalized = clampedDraft(
                ImageCropGeometry.resize(
                    rect: draftNormalized,
                    handle: handle,
                    to: normalized,
                    aspectRatio: aspect.lockedRatio(imageSize: imageSize)
                )
            )
            onDraftChanged?(draftNormalized)
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            cursor(for: handle, dragging: true).set()

        case .straighten:
            let center = CGPoint(x: cropViewRect().midX, y: cropViewRect().midY)
            let angle = atan2(p.y - center.y, p.x - center.x)
            var delta = angle - straightenDragStartPointerAngle
            // Unwrap to shortest path so crossing ±π doesn’t jump.
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            let next = ImageCropGeometry.clampStraightenRadians(straightenDragStartRadians + delta)
            if abs(next - straightenRadians) > 0.0002 {
                straightenRadians = next
                draftNormalized = clampedDraft(draftNormalized)
                onStraightenChanged?(straightenRadians)
                onDraftChanged?(draftNormalized)
            }
            // Always redraw so the angle badge tracks the cursor; orbit cursor with pointer.
            needsDisplay = true
            rotateCursor(at: p).set()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let endedStraighten: Bool
        if case .straighten = activeDrag {
            endedStraighten = true
        } else {
            endedStraighten = false
        }
        activeDrag = nil
        pointerInOverlay = convert(event.locationInWindow, from: nil)
        if endedStraighten {
            onStraightenDragEnded?()
        }
        window?.invalidateCursorRects(for: self)
        cursorUpdate(with: event)
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        pointerInOverlay = convert(event.locationInWindow, from: nil)
        cursorUpdate(with: event)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        if activeDrag == nil {
            pointerInOverlay = nil
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard imageFrameInOverlay.width > 1, imageFrameInOverlay.height > 1 else { return }

        let crop = cropViewRect()
        let image = imageFrameInOverlay

        // Pad outside the photo stays clear so the studio floor shows through exactly.
        // Soft-dim only discarded photo pixels; crop interior stays bright.
        outsideCropDim.setFill()
        let veil = NSBezierPath(rect: image)
        veil.append(NSBezierPath(rect: crop))
        veil.windingRule = .evenOdd
        veil.fill()

        NSColor.white.withAlphaComponent(0.95).setStroke()
        let border = NSBezierPath(rect: crop.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1.5
        border.stroke()

        // Rule-of-thirds guides.
        NSColor.white.withAlphaComponent(0.22).setStroke()
        let guides = NSBezierPath()
        for i in 1...2 {
            let fx = crop.minX + crop.width * CGFloat(i) / 3
            let fy = crop.minY + crop.height * CGFloat(i) / 3
            guides.move(to: NSPoint(x: fx, y: crop.minY))
            guides.line(to: NSPoint(x: fx, y: crop.maxY))
            guides.move(to: NSPoint(x: crop.minX, y: fy))
            guides.line(to: NSPoint(x: crop.maxX, y: fy))
        }
        guides.lineWidth = 1
        guides.stroke()

        for (_, loc) in handlePoints(in: crop) {
            drawHandle(at: loc)
        }

        if shouldShowAngleBadge {
            let degrees = ImageCropGeometry.straightenDegrees(from: straightenRadians)
            drawAngleBadge(degrees, in: crop)
        }
    }

    /// Photo plus margin — straighten lives here; crop never expands into the pad.
    private func toolingFrameInOverlay() -> CGRect {
        let pad = Self.toolingPad
        let expanded = imageFrameInOverlay.insetBy(dx: -pad, dy: -pad)
        return expanded.intersection(bounds.insetBy(dx: 2, dy: 2))
    }

    private var isStraightening: Bool {
        if case .straighten = activeDrag { return true }
        return false
    }

    private var shouldShowAngleBadge: Bool {
        if isStraightening { return true }
        let degrees = abs(ImageCropGeometry.straightenDegrees(from: straightenRadians))
        guard degrees >= 0.15, let p = pointerInOverlay else { return false }
        return isInStraightenZone(p)
    }

    private func isInStraightenZone(_ point: CGPoint) -> Bool {
        toolingFrameInOverlay().contains(point) && !cropViewRect().contains(point)
    }

    private func drawAngleBadge(_ degrees: CGFloat, in crop: CGRect) {
        let label = String(format: "%+.1f°", degrees)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = label.size(withAttributes: attrs)
        let pad: CGFloat = 6
        let badgeSize = CGSize(width: size.width + pad * 2, height: size.height + pad)

        let anchor = pointerInOverlay ?? CGPoint(x: crop.midX, y: crop.midY)
        var origin = CGPoint(
            x: anchor.x + badgeCursorOffset.x,
            y: anchor.y - badgeSize.height - badgeCursorOffset.y
        )

        // Keep the badge on the crop grid (inset), not outside / below the frame.
        let insetCrop = crop.insetBy(dx: 6, dy: 6)
        guard insetCrop.width >= badgeSize.width, insetCrop.height >= badgeSize.height else {
            // Tiny crop: center the badge.
            origin = CGPoint(
                x: crop.midX - badgeSize.width / 2,
                y: crop.midY - badgeSize.height / 2
            )
            drawBadge(label: label, attrs: attrs, origin: origin, size: badgeSize, pad: pad)
            return
        }
        origin.x = min(max(origin.x, insetCrop.minX), insetCrop.maxX - badgeSize.width)
        origin.y = min(max(origin.y, insetCrop.minY), insetCrop.maxY - badgeSize.height)
        drawBadge(label: label, attrs: attrs, origin: origin, size: badgeSize, pad: pad)
    }

    private func drawBadge(
        label: String,
        attrs: [NSAttributedString.Key: Any],
        origin: CGPoint,
        size: CGSize,
        pad: CGFloat
    ) {
        let badge = CGRect(origin: origin, size: size)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 6, yRadius: 6).fill()
        label.draw(
            at: CGPoint(x: badge.minX + pad, y: badge.minY + pad / 2),
            withAttributes: attrs
        )
    }

    private func drawHandle(at point: CGPoint) {
        let s = handleVisualSize
        let r = CGRect(x: point.x - s / 2, y: point.y - s / 2, width: s, height: s)
        NSColor.white.setFill()
        let fill = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
        fill.fill()
        NSColor.black.withAlphaComponent(0.4).setStroke()
        let stroke = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
        stroke.lineWidth = 1
        stroke.stroke()
    }

    private func cropViewRect() -> CGRect {
        let n = ImageCropGeometry.sanitized(draftNormalized)
        let f = imageFrameInOverlay
        var crop = CGRect(
            x: f.minX + n.minX * f.width,
            y: f.minY + n.minY * f.height,
            width: n.width * f.width,
            height: n.height * f.height
        ).standardized
        // Never draw outside the photo, even if normalized drifted.
        crop = crop.intersection(f)
        if crop.width < 1 || crop.height < 1 {
            return f.insetBy(dx: f.width * 0.1, dy: f.height * 0.1)
        }
        return crop
    }

    private func viewPointToNormalized(_ point: CGPoint) -> CGPoint? {
        let f = imageFrameInOverlay
        guard f.width > 1, f.height > 1 else { return nil }
        // Clamp to the photo frame so handles can’t drive the crop outside the image.
        let x = min(max(point.x, f.minX), f.maxX)
        let y = min(max(point.y, f.minY), f.maxY)
        return CGPoint(
            x: (x - f.minX) / f.width,
            y: (y - f.minY) / f.height
        )
    }

    private func handlePoints(in crop: CGRect) -> [(ImageCropHandle, CGPoint)] {
        [
            (.minXMinY, CGPoint(x: crop.minX, y: crop.minY)),
            (.maxXMinY, CGPoint(x: crop.maxX, y: crop.minY)),
            (.minXMaxY, CGPoint(x: crop.minX, y: crop.maxY)),
            (.maxXMaxY, CGPoint(x: crop.maxX, y: crop.maxY)),
            (.minY, CGPoint(x: crop.midX, y: crop.minY)),
            (.maxY, CGPoint(x: crop.midX, y: crop.maxY)),
            (.minX, CGPoint(x: crop.minX, y: crop.midY)),
            (.maxX, CGPoint(x: crop.maxX, y: crop.midY))
        ]
    }

    private func hitTestHandle(at point: CGPoint) -> ImageCropHandle? {
        for (handle, loc) in handlePoints(in: cropViewRect()) {
            let dx = point.x - loc.x
            let dy = point.y - loc.y
            if dx * dx + dy * dy <= handleHitSlop * handleHitSlop {
                return handle
            }
        }
        return nil
    }

    private func cursor(for handle: ImageCropHandle, dragging: Bool) -> NSCursor {
        switch handle {
        case .move:
            return dragging ? .closedHand : .openHand
        case .minX, .maxX:
            return .resizeLeftRight
        case .minY, .maxY:
            return .resizeUpDown
        case .minXMinY, .maxXMaxY:
            return diagonalResizeCursor(bottomLeadingToTopTrailing: true)
        case .maxXMinY, .minXMaxY:
            return diagonalResizeCursor(bottomLeadingToTopTrailing: false)
        }
    }

    private func diagonalResizeCursor(bottomLeadingToTopTrailing: Bool) -> NSCursor {
        if #available(macOS 15.0, *) {
            if bottomLeadingToTopTrailing {
                return NSCursor.frameResize(position: .bottomLeft, directions: .all)
            }
            return NSCursor.frameResize(position: .bottomRight, directions: .all)
        }
        return .crosshair
    }

    /// Lucide-style move-3d axes, rotated so the L corner tracks the pointer around the crop.
    /// Rest pose (0°) matches the bottom-leading corner; bottom-trailing is ~+90°, and so on.
    private func rotateCursor(at point: CGPoint?) -> NSCursor {
        let crop = cropViewRect()
        let center = CGPoint(x: crop.midX, y: crop.midY)
        // Prefer live pointer; fall back to bottom-leading so rest pose matches the icon.
        let p = point ?? CGPoint(x: crop.minX, y: crop.minY)
        let dx = p.x - center.x
        let dy = p.y - center.y
        let pointerDegrees: CGFloat
        if abs(dx) < 0.5, abs(dy) < 0.5 {
            pointerDegrees = -135 // treat center as SW
        } else {
            pointerDegrees = atan2(dy, dx) * 180 / .pi
        }
        // Icon’s L lives at SW (−135°). Offset so that corner reads as 0°.
        let rotationDegrees = pointerDegrees - (-135)
        let key = Int(rotationDegrees.rounded())
        if let cached = rotateCursorCache[key] {
            return cached
        }
        let cursor = Self.makeMove3DCursor(rotationDegrees: rotationDegrees)
        rotateCursorCache[key] = cursor
        return cursor
    }

    /// Lucide `move-3d`: L axes + diagonal depth line + arrowheads on X/Y.
    private static func makeMove3DCursor(rotationDegrees: CGFloat) -> NSCursor {
        let size: CGFloat = 36
        let padded = NSSize(width: size, height: size)
        let cursorImage = NSImage(size: padded, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            ctx.translateBy(x: rect.midX, y: rect.midY)
            // Orbit around the crop (CCW positive in AppKit y-up space).
            ctx.rotate(by: rotationDegrees * .pi / 180)
            // Map lucide’s 24×24 SVG (y-down) into centered y-up drawing.
            let iconScale: CGFloat = 18.0 / 24.0
            ctx.scaleBy(x: iconScale, y: iconScale)
            ctx.scaleBy(x: 1, y: -1)
            ctx.translateBy(x: -12, y: -12)

            let path = CGMutablePath()
            // M5 3 v16 h16
            path.move(to: CGPoint(x: 5, y: 3))
            path.addLine(to: CGPoint(x: 5, y: 19))
            path.addLine(to: CGPoint(x: 21, y: 19))
            // m5 19 6-6
            path.move(to: CGPoint(x: 5, y: 19))
            path.addLine(to: CGPoint(x: 11, y: 13))
            // m2 6 3-3 3 3  (Y arrow)
            path.move(to: CGPoint(x: 2, y: 6))
            path.addLine(to: CGPoint(x: 5, y: 3))
            path.addLine(to: CGPoint(x: 8, y: 6))
            // m18 16 3 3-3 3  (X arrow)
            path.move(to: CGPoint(x: 18, y: 16))
            path.addLine(to: CGPoint(x: 21, y: 19))
            path.addLine(to: CGPoint(x: 18, y: 22))

            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            // Dark halo for contrast on light photo areas.
            ctx.addPath(path)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(3.4)
            ctx.strokePath()

            ctx.addPath(path)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(2.0)
            ctx.strokePath()

            ctx.restoreGState()
            return true
        }
        return NSCursor(
            image: cursorImage,
            hotSpot: NSPoint(x: size / 2, y: size / 2)
        )
    }
}
