import AppKit

enum LibraryTileSelectionChrome: Equatable {
    case none
    case preview
    case selected
}

protocol LibrarySelectableGridItem: AnyObject {
    func applySelectionChrome(_ chrome: LibraryTileSelectionChrome)
    var onDeselectRequested: (() -> Void)? { get set }
}

// MARK: - Collection view with marquee + paint-select

final class LibraryGridCollectionView: NSCollectionView {
    var contextMenuProvider: ((NSEvent, NSCollectionView) -> NSMenu?)?
    /// Called when Esc / ⌘A / arrows need browse-level handling.
    var onKeyCommand: ((LibraryGridKeyCommand) -> Bool)?
    /// Host drives controller selection + tile chrome.
    weak var multiSelectHost: LibraryGridMultiSelectHost?

    private enum DragKind {
        case none
        case pendingOpen(IndexPath)
        case marquee
        case paint
        case holdSelection
    }

    private var dragKind: DragKind = .none
    private var mouseDownPoint: NSPoint = .zero
    private var baseSelection = IndexSet()
    private var livePreview = IndexSet()
    private var lastPaintIndex: Int?
    private let dragThreshold: CGFloat = 5

    private let marqueeOverlay = MarqueeOverlayView()
    private let countBadge = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureOverlays()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureOverlays()
    }

    private func configureOverlays() {
        marqueeOverlay.isHidden = true
        marqueeOverlay.wantsLayer = true
        addSubview(marqueeOverlay)

        countBadge.isHidden = true
        countBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        countBadge.textColor = .labelColor
        countBadge.drawsBackground = true
        countBadge.backgroundColor = LaughTheme.chromeActiveFill()
        countBadge.wantsLayer = true
        countBadge.layer?.cornerRadius = 4
        countBadge.layer?.masksToBounds = true
        countBadge.alignment = .center
        addSubview(countBadge)
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if let menu = contextMenuProvider?(event, self) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenuProvider?(event, self) ?? super.menu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.shift) {
            dragKind = .none
            super.mouseDown(with: event)
            return
        }

        mouseDownPoint = convert(event.locationInWindow, from: nil)
        baseSelection = multiSelectHost?.committedSelectionIndices() ?? []
        livePreview = baseSelection
        lastPaintIndex = nil

        if let indexPath = indexPathForItem(at: mouseDownPoint) {
            let index = indexPath.item
            if baseSelection.contains(index) {
                dragKind = .holdSelection
            } else {
                dragKind = .pendingOpen(indexPath)
            }
        } else {
            dragKind = .marquee
            livePreview = IndexSet()
            multiSelectHost?.selectionGestureDidUpdatePreview(livePreview)
            updateMarquee(from: mouseDownPoint, to: mouseDownPoint, count: 0)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        switch dragKind {
        case .none:
            super.mouseDragged(with: event)
        case .holdSelection:
            break
        case .pendingOpen:
            let point = convert(event.locationInWindow, from: nil)
            let distance = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
            guard distance >= dragThreshold else { return }
            // Rubber-band from the press point so the selection zone is always visible.
            dragKind = .marquee
            livePreview = indicesIntersecting(Self.normalizedRect(mouseDownPoint, point))
            multiSelectHost?.selectionGestureDidUpdatePreview(livePreview)
            updateMarquee(from: mouseDownPoint, to: point, count: livePreview.count)
        case .paint:
            let point = convert(event.locationInWindow, from: nil)
            paintSelect(at: point)
            updateCountBadge(at: point, count: livePreview.count)
        case .marquee:
            let point = convert(event.locationInWindow, from: nil)
            let rect = Self.normalizedRect(mouseDownPoint, point)
            livePreview = indicesIntersecting(rect)
            multiSelectHost?.selectionGestureDidUpdatePreview(livePreview)
            updateMarquee(from: mouseDownPoint, to: point, count: livePreview.count)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer {
            dragKind = .none
            hideMarquee()
        }

        switch dragKind {
        case .none:
            super.mouseUp(with: event)
        case .holdSelection:
            // No drag-reorder yet: plain click on a selected tile opens it.
            if hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) < dragThreshold,
               let indexPath = indexPathForItem(at: mouseDownPoint) {
                multiSelectHost?.selectionGestureDidRequestOpen(at: indexPath.item)
            }
        case .pendingOpen(let indexPath):
            multiSelectHost?.selectionGestureDidRequestOpen(at: indexPath.item)
        case .paint, .marquee:
            let distance = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y)
            if case .marquee = dragKind, distance < dragThreshold {
                // Empty-space click clears selection.
                multiSelectHost?.selectionGestureDidCommit(IndexSet())
            } else {
                multiSelectHost?.selectionGestureDidCommit(livePreview)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if handleKeyEvent(event) { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleKeyEvent(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard let onKeyCommand else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53 { // Escape
            return onKeyCommand(.escape)
        }
        if flags.contains(.command), event.charactersIgnoringModifiers == "a" {
            return onKeyCommand(.selectAll)
        }
        let extending = flags.contains(.shift)
        switch event.keyCode {
        case 123: return onKeyCommand(.move(-1, extending))  // left
        case 124: return onKeyCommand(.move(1, extending))   // right
        case 125: return onKeyCommand(.move(rowDelta(forward: true), extending))  // down
        case 126: return onKeyCommand(.move(rowDelta(forward: false), extending)) // up
        default: return false
        }
    }

    private func rowDelta(forward: Bool) -> Int {
        let columns = max(1, estimatedColumnCount())
        return forward ? columns : -columns
    }

    private func estimatedColumnCount() -> Int {
        guard let layout = collectionViewLayout as? NSCollectionViewGridLayout else { return 4 }
        let inset = layout.margins.left + layout.margins.right
        let available = max(1, bounds.width - inset)
        let itemWidth = max(1, layout.minimumItemSize.width)
        let spacing = layout.minimumInteritemSpacing
        return max(1, Int((available + spacing) / (itemWidth + spacing)))
    }

    private func paintSelect(at point: NSPoint) {
        guard let indexPath = indexPathForItem(at: point) else { return }
        let index = indexPath.item
        guard lastPaintIndex != index else { return }
        lastPaintIndex = index
        livePreview.insert(index)
        multiSelectHost?.selectionGestureDidUpdatePreview(livePreview)
    }

    private func indicesIntersecting(_ rect: NSRect) -> IndexSet {
        var result = IndexSet()
        let count = numberOfItems(inSection: 0)
        for item in 0..<count {
            let path = IndexPath(item: item, section: 0)
            let frame: NSRect
            if let attrs = layoutAttributesForItem(at: path) {
                frame = attrs.frame
            } else if let itemView = self.item(at: path)?.view {
                frame = convert(itemView.bounds, from: itemView)
            } else {
                continue
            }
            if frame.intersects(rect) {
                result.insert(item)
            }
        }
        return result
    }

    private func updateMarquee(from start: NSPoint, to end: NSPoint, count: Int) {
        let rect = Self.normalizedRect(start, end)
        marqueeOverlay.frame = rect
        marqueeOverlay.isHidden = false
        marqueeOverlay.refreshAppearance()
        // Collection items are added after overlays — keep the rubber band above tiles.
        addSubview(marqueeOverlay, positioned: .above, relativeTo: nil)
        updateCountBadge(at: end, count: count)
    }

    private func updateMarqueeHidden() {
        marqueeOverlay.isHidden = true
    }

    private func hideMarquee() {
        marqueeOverlay.isHidden = true
        countBadge.isHidden = true
    }

    private func updateCountBadge(at point: NSPoint, count: Int) {
        guard count > 0 else {
            countBadge.isHidden = true
            return
        }
        countBadge.stringValue = "  \(count) selected  "
        countBadge.sizeToFit()
        var origin = NSPoint(x: point.x + 12, y: point.y - countBadge.bounds.height - 8)
        origin.x = min(max(0, origin.x), bounds.width - countBadge.bounds.width)
        origin.y = min(max(0, origin.y), bounds.height - countBadge.bounds.height)
        countBadge.setFrameOrigin(origin)
        countBadge.isHidden = false
        countBadge.backgroundColor = LaughTheme.chromeActiveFill(appearance: effectiveAppearance)
        addSubview(countBadge, positioned: .above, relativeTo: nil)
    }

    private static func normalizedRect(_ a: NSPoint, _ b: NSPoint) -> NSRect {
        let x = min(a.x, b.x)
        let y = min(a.y, b.y)
        return NSRect(x: x, y: y, width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

enum LibraryGridKeyCommand {
    case escape
    case selectAll
    case move(Int, Bool)
}

protocol LibraryGridMultiSelectHost: AnyObject {
    func committedSelectionIndices() -> IndexSet
    func selectionGestureDidUpdatePreview(_ indices: IndexSet)
    func selectionGestureDidCommit(_ indices: IndexSet)
    func selectionGestureDidRequestOpen(at index: Int)
}

private final class MarqueeOverlayView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
        refreshAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshAppearance() {
        let appearance = effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Soft teal wash + clearer stroke so the drag zone reads over thumbnails.
        let fillAlpha: CGFloat = isDark ? 0.22 : 0.16
        let strokeAlpha: CGFloat = isDark ? 0.75 : 0.65
        layer?.backgroundColor = LaughTheme.interactiveAccent.withAlphaComponent(fillAlpha).cgColor
        layer?.borderWidth = 1.5
        layer?.borderColor = LaughTheme.interactiveAccent.withAlphaComponent(strokeAlpha).cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearance()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
