import AppKit

/// Batch tab contents: selected siblings as a small tile grid (ADR 0006).
/// Right-rail develop params stamp onto the set automatically while this tab is selected.
/// Each tile’s Dry / Wet mix sits at the bottom and appears on hover.
final class ImageBatchCatalogView: NSView {
    var onClearSelection: (() -> Void)?
    var onRevealItem: ((URL) -> Void)?
    var onMixChange: ((URL, Double) -> Void)?
    var onMixCommit: ((URL, Double) -> Void)?
    var onRemoveItem: ((URL) -> Void)?

    private let emptyLabel = NSTextField(wrappingLabelWithString: "Select 2+ in the filmstrip\n(⌘-click or ⇧-click)")
    private let countLabel = NSTextField(labelWithString: "")
    private let listStack = ImmersivePanelStackView()
    private let scrollView = NSScrollView()
    private let documentView = SettingsScrollDocumentView()
    private let clearButton = CommitFooterActionButton(
        title: "Clear selection",
        symbol: "xmark",
        emphasized: false,
        toolTip: "Clear batch selection"
    )
    private let actionsColumn = NSStackView()
    private var tilesByPath: [String: ImageBatchCatalogTileView] = [:]
    private var configuredPaths: [String] = []
    private let topOverflowFade = ScrollOverflowFadeView()
    private let bottomOverflowFade = ScrollOverflowFadeView()
    private static let overflowFadeHeight: CGFloat = 28

    private static let tileSpacing: CGFloat = 6
    private static let columns = 2
    /// Match Gallery mosaic (~16:9).
    fileprivate static let tileAspectWidth: CGFloat = 16
    fileprivate static let tileAspectHeight: CGFloat = 9
    /// Decode cap in points; generator also floors at 960px so Retina tiles stay sharp.
    fileprivate static let thumbnailMaxSide: CGFloat = 480

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        countLabel.textColor = .labelColor
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = Self.tileSpacing
        listStack.translatesAutoresizingMaskIntoConstraints = false

        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(listStack)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = documentView

        actionsColumn.orientation = .vertical
        actionsColumn.alignment = .leading
        actionsColumn.spacing = 8
        actionsColumn.translatesAutoresizingMaskIntoConstraints = false
        actionsColumn.addArrangedSubview(clearButton)

        clearButton.target = self
        clearButton.action = #selector(clearPressed)

        addSubview(emptyLabel)
        addSubview(countLabel)
        addSubview(scrollView)
        addSubview(actionsColumn)
        addSubview(topOverflowFade)
        addSubview(bottomOverflowFade)

        topOverflowFade.edge = .top
        topOverflowFade.translatesAutoresizingMaskIntoConstraints = false
        bottomOverflowFade.edge = .bottom
        bottomOverflowFade.translatesAutoresizingMaskIntoConstraints = false
        refreshOverflowFloor()
        topOverflowFade.attach(to: scrollView)
        bottomOverflowFade.attach(to: scrollView)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -24),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),

            countLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            countLabel.topAnchor.constraint(equalTo: topAnchor),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: countLabel.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: actionsColumn.topAnchor, constant: -10),

            listStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            listStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            listStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            actionsColumn.leadingAnchor.constraint(equalTo: leadingAnchor),
            actionsColumn.trailingAnchor.constraint(equalTo: trailingAnchor),
            actionsColumn.bottomAnchor.constraint(equalTo: bottomAnchor),
            clearButton.widthAnchor.constraint(equalTo: actionsColumn.widthAnchor),

            topOverflowFade.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            topOverflowFade.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            topOverflowFade.topAnchor.constraint(equalTo: scrollView.topAnchor),
            topOverflowFade.heightAnchor.constraint(equalToConstant: Self.overflowFadeHeight),
            bottomOverflowFade.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            bottomOverflowFade.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            bottomOverflowFade.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            bottomOverflowFade.heightAnchor.constraint(equalToConstant: Self.overflowFadeHeight)
        ])

        configure(urls: [], thumbnails: [:], mixByPath: [:])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(urls: [URL], thumbnails: [URL: NSImage], mixByPath: [String: Double]) {
        let active = urls.count >= 2
        emptyLabel.isHidden = active
        countLabel.isHidden = !active
        scrollView.isHidden = !active
        actionsColumn.isHidden = !active
        clearButton.isEnabled = active

        countLabel.stringValue = active ? "\(urls.count) selected" : ""

        let items: [(url: URL, thumb: NSImage?, mix: Double)] = urls.map { url in
            let key = url.standardizedFileURL
            let thumb = thumbnails[key] ?? thumbnails[url]
            return (url: url, thumb: thumb, mix: mixByPath[key.path] ?? 1)
        }
        let paths = items.map { $0.url.standardizedFileURL.path }

        if paths == configuredPaths, !paths.isEmpty {
            for item in items {
                tilesByPath[item.url.standardizedFileURL.path]?.configure(
                    url: item.url,
                    thumb: item.thumb,
                    mix: item.mix,
                    appearance: effectiveAppearance
                )
            }
            refreshChrome()
            return
        }

        configuredPaths = paths
        tilesByPath.removeAll()
        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        var index = 0
        while index < items.count {
            let row = ImmersivePanelStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.distribution = .fillEqually
            row.spacing = Self.tileSpacing
            row.translatesAutoresizingMaskIntoConstraints = false

            let end = min(index + Self.columns, items.count)
            for item in items[index..<end] {
                let tile = ImageBatchCatalogTileView()
                tile.configure(
                    url: item.url,
                    thumb: item.thumb,
                    mix: item.mix,
                    appearance: effectiveAppearance
                )
                tile.onReveal = { [weak self] url in
                    self?.onRevealItem?(url)
                }
                tile.onMixChange = { [weak self] url, amount in
                    self?.onMixChange?(url, amount)
                }
                tile.onMixCommit = { [weak self] url, amount in
                    self?.onMixCommit?(url, amount)
                }
                tile.onRemove = { [weak self] url in
                    self?.onRemoveItem?(url)
                }
                tilesByPath[item.url.standardizedFileURL.path] = tile
                row.addArrangedSubview(tile)
            }
            if end - index == 1 {
                let spacer = NSView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                row.addArrangedSubview(spacer)
            }

            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            index = end
        }

        layoutSubtreeIfNeeded()
        let width = max(scrollView.contentView.bounds.width, 1)
        let height = max(listStack.fittingSize.height, 1)
        documentView.setFrameSize(NSSize(width: width, height: height))
        refreshChrome()
        refreshOverflowFades()
    }

    override func layout() {
        super.layout()
        let width = max(scrollView.contentView.bounds.width, 1)
        let height = max(listStack.fittingSize.height, 1)
        if !tileRowsAreEmpty {
            documentView.setFrameSize(NSSize(width: width, height: height))
        }
        refreshOverflowFades()
    }

    private var tileRowsAreEmpty: Bool {
        listStack.arrangedSubviews.isEmpty
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshChrome()
        refreshOverflowFloor()
    }

    private func refreshChrome() {
        let appearance = effectiveAppearance
        clearButton.refreshChrome(appearance: appearance)
    }

    private func refreshOverflowFloor() {
        let floor = LaughTheme.imageStudioFloorColor(appearance: effectiveAppearance)
        topOverflowFade.floorColor = floor
        bottomOverflowFade.floorColor = floor
    }

    private func refreshOverflowFades() {
        if !scrollView.isHidden {
            addSubview(topOverflowFade, positioned: .above, relativeTo: scrollView)
            addSubview(bottomOverflowFade, positioned: .above, relativeTo: scrollView)
        }
        topOverflowFade.refreshOverflow(animated: false)
        bottomOverflowFade.refreshOverflow(animated: false)
    }

    @objc private func clearPressed() { onClearSelection?() }
}

// MARK: - Tile

private final class ImageBatchCatalogTileView: NSView {
    var onReveal: ((URL) -> Void)?
    var onMixChange: ((URL, Double) -> Void)?
    var onMixCommit: ((URL, Double) -> Void)?
    var onRemove: ((URL) -> Void)?

    private let coverView = ImageBatchCatalogCoverView()
    private let overlay = NSView()
    private let dryLabel = NSTextField(labelWithString: "Dry")
    private let wetLabel = NSTextField(labelWithString: "Wet")
    private let slider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let removeHost = CatalogHoverTrashHost()
    private let removeButton = NSButton(title: "", target: nil, action: nil)

    private var url: URL?
    private var loadToken = UUID()
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false
    private var isRemoveHovered = false
    private var isDraggingMix = false
    private var mixMouseUpMonitor: Any?
    private var hoverMoveMonitor: Any?

    override var mouseDownCanMoveWindow: Bool { false }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        coverView.translatesAutoresizingMaskIntoConstraints = false

        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        overlay.alphaValue = 0
        overlay.isHidden = true

        dryLabel.translatesAutoresizingMaskIntoConstraints = false
        dryLabel.font = .systemFont(ofSize: 8, weight: .semibold)
        dryLabel.textColor = .white.withAlphaComponent(0.85)
        dryLabel.setContentHuggingPriority(.required, for: .horizontal)

        wetLabel.translatesAutoresizingMaskIntoConstraints = false
        wetLabel.font = .systemFont(ofSize: 8, weight: .semibold)
        wetLabel.textColor = .white.withAlphaComponent(0.85)
        wetLabel.setContentHuggingPriority(.required, for: .horizontal)

        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.isContinuous = true
        slider.controlSize = .mini
        slider.focusRingType = .none
        slider.target = self
        slider.action = #selector(mixChanged(_:))
        slider.setAccessibilityLabel("Dry / Wet")
        if let cell = slider.cell {
            cell.isContinuous = true
        }
        slider.useFlatBarAppearance(
            trackHeight: 3,
            filledColor: LaughTheme.interactiveAccent,
            showsKnob: true
        )

        removeHost.translatesAutoresizingMaskIntoConstraints = false
        removeHost.surface = .onPhoto
        removeHost.alphaValue = 0
        removeHost.isHidden = true
        removeHost.onHover = { [weak self] _ in
            self?.syncHoverFromWindow(animated: false)
        }

        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.isBordered = false
        removeButton.bezelStyle = .regularSquare
        removeButton.imagePosition = .imageOnly
        removeButton.focusRingType = .none
        removeButton.target = self
        removeButton.action = #selector(removePressed)
        removeButton.toolTip = "Remove from batch"
        removeButton.setAccessibilityLabel("Remove from batch")
        if let image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Remove from batch") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            let configured = image.withSymbolConfiguration(config) ?? image
            configured.isTemplate = true
            removeButton.image = configured
        }
        removeButton.contentTintColor = NSColor.black
        removeButton.shadow = nil

        addSubview(coverView)
        addSubview(overlay)
        addSubview(removeHost)
        overlay.addSubview(dryLabel)
        overlay.addSubview(slider)
        overlay.addSubview(wetLabel)
        removeHost.addSubview(removeButton)

        let aspect = heightAnchor.constraint(
            equalTo: widthAnchor,
            multiplier: ImageBatchCatalogView.tileAspectHeight / ImageBatchCatalogView.tileAspectWidth
        )
        aspect.priority = .required
        NSLayoutConstraint.activate([
            aspect,
            widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
            coverView.leadingAnchor.constraint(equalTo: leadingAnchor),
            coverView.trailingAnchor.constraint(equalTo: trailingAnchor),
            coverView.topAnchor.constraint(equalTo: topAnchor),
            coverView.bottomAnchor.constraint(equalTo: bottomAnchor),

            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            overlay.heightAnchor.constraint(equalToConstant: 22),

            dryLabel.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 4),
            dryLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            wetLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -4),
            wetLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            slider.leadingAnchor.constraint(equalTo: dryLabel.trailingAnchor, constant: 3),
            slider.trailingAnchor.constraint(equalTo: wetLabel.leadingAnchor, constant: -3),
            slider.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            slider.heightAnchor.constraint(equalToConstant: 14),

            removeHost.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            removeHost.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            removeHost.widthAnchor.constraint(equalToConstant: 22),
            removeHost.heightAnchor.constraint(equalToConstant: 22),
            removeButton.centerXAnchor.constraint(equalTo: removeHost.centerXAnchor),
            removeButton.centerYAnchor.constraint(equalTo: removeHost.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 16),
            removeButton.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(url: URL, thumb: NSImage?, mix: Double, appearance: NSAppearance) {
        let sameURL = self.url?.standardizedFileURL == url.standardizedFileURL
        self.url = url
        toolTip = url.lastPathComponent
        setAccessibilityLabel(url.lastPathComponent)
        if !isDraggingMix {
            slider.doubleValue = mix
        }
        slider.identifier = NSUserInterfaceItemIdentifier(url.standardizedFileURL.path)
        refreshChrome(appearance: appearance)
        if sameURL {
            if !coverView.hasPhoto, let thumb {
                coverView.setPhoto(thumb)
            }
            return
        }
        loadToken = UUID()
        coverView.setPhoto(thumb)
        updateOverlayVisibility(animated: false)
        loadCatalogThumbnail(for: url)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            isHovered = false
            isRemoveHovered = false
            updateOverlayVisibility(animated: false)
            return
        }
        guard let url, !coverView.hasPhoto else { return }
        loadCatalogThumbnail(for: url)
    }

    private func loadCatalogThumbnail(for url: URL) {
        let token = loadToken
        let scale = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? MediaThumbnailGenerator.defaultScreenScale()
        let maxSide = ImageBatchCatalogView.thumbnailMaxSide
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let kind = MediaKindDetector.kind(for: url)
            let image = MediaThumbnailGenerator.thumbnail(
                for: url,
                kind: kind,
                maxSide: maxSide,
                screenScale: scale
            )
            DispatchQueue.main.async {
                guard let self, self.loadToken == token, self.url?.standardizedFileURL == url.standardizedFileURL else {
                    return
                }
                if let image {
                    self.coverView.setPhoto(image)
                }
            }
        }
    }

    func refreshChrome(appearance: NSAppearance) {
        layer?.backgroundColor = LaughTheme.chromeHoverFill(appearance: appearance).cgColor
        slider.useFlatBarAppearance(
            trackHeight: 3,
            filledColor: LaughTheme.interactiveAccent,
            showsKnob: true
        )
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if removeHost.alphaValue > 0.01, removeHost.frame.contains(local) {
            super.mouseDown(with: event)
            return
        }
        if overlay.alphaValue > 0.01, overlay.frame.contains(local) {
            super.mouseDown(with: event)
            return
        }
        guard let url else { return }
        onReveal?(url)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        syncHoverFromWindow(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        // Slider / trash have their own tracking; parent exit can fire while still inside.
        DispatchQueue.main.async { [weak self] in
            self?.syncHoverFromWindow(animated: true)
        }
    }

    private func pointerLocationInTile() -> NSPoint? {
        CatalogHoverPointer.location(in: self)
    }

    private func syncHoverFromWindow(animated: Bool) {
        let loc = pointerLocationInTile()
        let inside = loc.map { bounds.contains($0) } ?? false
        isHovered = inside
        let onTrash = loc.map { removeHost.frame.contains($0) } ?? false
        isRemoveHovered = inside && onTrash
        removeHost.setHovered(isRemoveHovered, appearance: effectiveAppearance)
        removeButton.contentTintColor = NSColor.black
        updateOverlayVisibility(animated: animated)
    }

    private func updateOverlayVisibility(animated: Bool) {
        let show = isHovered || isDraggingMix
        let apply = {
            self.overlay.alphaValue = show ? 1 : 0
            self.overlay.isHidden = !show
            self.removeHost.alphaValue = show ? 1 : 0
            self.removeHost.isHidden = !show
        }
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.allowsImplicitAnimation = true
                apply()
            }
        } else {
            apply()
        }
        refreshHoverMoveMonitor(needed: show)
    }

    private func refreshHoverMoveMonitor(needed: Bool) {
        if needed {
            guard hoverMoveMonitor == nil else { return }
            hoverMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
                self?.syncHoverFromWindow(animated: false)
                return event
            }
            return
        }
        if let hoverMoveMonitor {
            NSEvent.removeMonitor(hoverMoveMonitor)
            self.hoverMoveMonitor = nil
        }
    }

    @objc private func removePressed() {
        guard let url else { return }
        onRemove?(url)
    }

    @objc private func mixChanged(_ sender: NSSlider) {
        guard let url else { return }
        beginMixDragIfNeeded()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        onMixChange?(url, sender.doubleValue)
        CATransaction.commit()
    }

    private func beginMixDragIfNeeded() {
        guard !isDraggingMix else { return }
        isDraggingMix = true
        updateOverlayVisibility(animated: false)
        if mixMouseUpMonitor == nil {
            mixMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
                self?.endMixDrag()
                return event
            }
        }
    }

    private func endMixDrag() {
        if let mixMouseUpMonitor {
            NSEvent.removeMonitor(mixMouseUpMonitor)
            self.mixMouseUpMonitor = nil
        }
        guard isDraggingMix else { return }
        isDraggingMix = false
        if let url {
            onMixCommit?(url, slider.doubleValue)
        }
        syncHoverFromWindow(animated: true)
    }

    deinit {
        if let mixMouseUpMonitor {
            NSEvent.removeMonitor(mixMouseUpMonitor)
        }
        if let hoverMoveMonitor {
            NSEvent.removeMonitor(hoverMoveMonitor)
        }
    }
}

/// Full-bleed 16:9 cover (same gravity as library Gallery tiles).
private final class ImageBatchCatalogCoverView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        if let current = layer?.contents {
            layer?.contents = current
        }
    }

    func setPhoto(_ image: NSImage?) {
        let scale = window?.backingScaleFactor
            ?? layer?.contentsScale
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        layer?.contentsScale = scale
        layer?.contentsGravity = .resizeAspectFill
        guard let image else {
            layer?.contents = nil
            return
        }
        layer?.contents = image.layerContents(forContentsScale: scale)
    }

    var hasPhoto: Bool {
        layer?.contents != nil
    }
}

enum CatalogHoverPointer {
    static func location(in view: NSView) -> NSPoint? {
        guard let window = view.window else { return nil }
        return view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
    }
}

enum CatalogHoverTrashSurface {
    case onPhoto
    case onChrome
}

/// Trash affordance without a dark disc — frost on photos, grey chrome wash on lists.
final class CatalogHoverTrashHost: NSView {
    var onHover: ((Bool) -> Void)?
    var surface: CatalogHoverTrashSurface = .onPhoto
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 0
        setHovered(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    func setHovered(_ hovering: Bool, appearance: NSAppearance? = nil) {
        let appearance = appearance ?? effectiveAppearance
        switch surface {
        case .onPhoto:
            layer?.backgroundColor = hovering
                ? NSColor(calibratedWhite: 0.52, alpha: 1).cgColor
                : NSColor(calibratedWhite: 0.68, alpha: 1).cgColor
        case .onChrome:
            layer?.backgroundColor = hovering
                ? LaughTheme.chromeHoverFill(appearance: appearance).cgColor
                : NSColor.clear.cgColor
        }
    }
}
