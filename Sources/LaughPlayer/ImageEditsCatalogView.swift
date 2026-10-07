import AppKit

/// Edits tab: folder stills that have a saved or unsaved develop look (ADR 0006).
final class ImageEditsCatalogView: NSView {
    var onRevealItem: ((URL) -> Void)?
    var onSaveAllUnsaved: (() -> Void)?
    var onClearEdit: ((URL) -> Void)?
    var onClearAllEdits: (() -> Void)?

    private let emptyLabel = NSTextField(wrappingLabelWithString: "No single-image edits in this folder yet.\nBatch looks stay in Batch.")
    private let countLabel = NSTextField(labelWithString: "")
    private let listStack = ImmersivePanelStackView()
    private let scrollView = NSScrollView()
    private let documentView = SettingsScrollDocumentView()
    private let saveAllButton = CommitFooterActionButton(
        title: "Save All Unsaved",
        symbol: "square.and.arrow.down",
        emphasized: true,
        toolTip: "Write all unsaved looks in this folder to Laugh’s edit store"
    )
    private let clearAllButton = CommitFooterActionButton(
        title: "Clear all",
        symbol: "trash",
        emphasized: false,
        toolTip: "Remove every saved and unsaved look in this folder"
    )
    private let actionsColumn = NSStackView()
    private let topOverflowFade = ScrollOverflowFadeView()
    private let bottomOverflowFade = ScrollOverflowFadeView()
    private var configuredItems: [Item] = []
    private static let overflowFadeHeight: CGFloat = 28

    struct Item: Equatable {
        var url: URL
        var isUnsaved: Bool
        var isSaved: Bool
    }

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
        listStack.spacing = 6
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

        saveAllButton.target = self
        saveAllButton.action = #selector(saveAllPressed)
        saveAllButton.translatesAutoresizingMaskIntoConstraints = false

        clearAllButton.target = self
        clearAllButton.action = #selector(clearAllPressed)
        clearAllButton.translatesAutoresizingMaskIntoConstraints = false

        actionsColumn.orientation = .vertical
        actionsColumn.alignment = .leading
        actionsColumn.spacing = 8
        actionsColumn.translatesAutoresizingMaskIntoConstraints = false
        actionsColumn.addArrangedSubview(saveAllButton)
        actionsColumn.addArrangedSubview(clearAllButton)

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
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
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
            saveAllButton.widthAnchor.constraint(equalTo: actionsColumn.widthAnchor),
            clearAllButton.widthAnchor.constraint(equalTo: actionsColumn.widthAnchor),

            topOverflowFade.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            topOverflowFade.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            topOverflowFade.topAnchor.constraint(equalTo: scrollView.topAnchor),
            topOverflowFade.heightAnchor.constraint(equalToConstant: Self.overflowFadeHeight),
            bottomOverflowFade.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            bottomOverflowFade.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            bottomOverflowFade.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            bottomOverflowFade.heightAnchor.constraint(equalToConstant: Self.overflowFadeHeight)
        ])

        configure(items: [], thumbnails: [:])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(items: [Item], thumbnails: [URL: NSImage]) {
        let hasItems = !items.isEmpty
        let unsavedCount = items.filter(\.isUnsaved).count
        emptyLabel.isHidden = hasItems
        countLabel.isHidden = !hasItems
        scrollView.isHidden = !hasItems
        actionsColumn.isHidden = !hasItems
        saveAllButton.isHidden = unsavedCount == 0
        saveAllButton.isEnabled = unsavedCount > 0
        clearAllButton.isHidden = !hasItems
        clearAllButton.isEnabled = hasItems

        if hasItems {
            let unsavedNote = unsavedCount > 0 ? " · \(unsavedCount) unsaved" : ""
            countLabel.stringValue = "\(items.count) edited\(unsavedNote)"
        } else {
            countLabel.stringValue = ""
        }

        if items == configuredItems {
            refreshOverflowFades()
            return
        }
        configuredItems = items

        listStack.arrangedSubviews.forEach {
            listStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for item in items {
            let row = ImageEditsCatalogRow()
            row.configure(item: item, thumb: thumbnails[item.url.standardizedFileURL], appearance: effectiveAppearance)
            row.onReveal = { [weak self] url in
                self?.onRevealItem?(url)
            }
            row.onClear = { [weak self] url in
                self?.onClearEdit?(url)
            }
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
        }
        layoutSubtreeIfNeeded()
        let width = max(scrollView.contentView.bounds.width, 1)
        let height = max(listStack.fittingSize.height, 1)
        documentView.setFrameSize(NSSize(width: width, height: height))
        saveAllButton.refreshChrome(appearance: effectiveAppearance)
        clearAllButton.refreshChrome(appearance: effectiveAppearance)
        refreshOverflowFades()
    }

    override func layout() {
        super.layout()
        let width = max(scrollView.contentView.bounds.width, 1)
        let height = max(listStack.fittingSize.height, 1)
        if !listStack.arrangedSubviews.isEmpty {
            documentView.setFrameSize(NSSize(width: width, height: height))
        }
        refreshOverflowFades()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        saveAllButton.refreshChrome(appearance: effectiveAppearance)
        clearAllButton.refreshChrome(appearance: effectiveAppearance)
        refreshOverflowFloor()
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

    @objc private func saveAllPressed() {
        onSaveAllUnsaved?()
    }

    @objc private func clearAllPressed() {
        onClearAllEdits?()
    }
}

private final class ImageEditsCatalogRow: NSView {
    var onReveal: ((URL) -> Void)?
    var onClear: ((URL) -> Void)?

    private let imageView = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let removeHost = CatalogHoverTrashHost()
    private let removeButton = NSButton(title: "", target: nil, action: nil)

    private var url: URL?
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false
    private var hoverMoveMonitor: Any?

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 4
        imageView.layer?.masksToBounds = true

        name.translatesAutoresizingMaskIntoConstraints = false
        name.font = .systemFont(ofSize: 12, weight: .medium)
        name.textColor = .labelColor
        name.lineBreakMode = .byTruncatingMiddle

        removeHost.translatesAutoresizingMaskIntoConstraints = false
        removeHost.surface = .onChrome
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
        removeButton.action = #selector(clearPressed)
        removeButton.toolTip = "Clear saved look"
        removeButton.setAccessibilityLabel("Clear saved look")
        if let image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear saved look") {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            let configured = image.withSymbolConfiguration(config) ?? image
            configured.isTemplate = true
            removeButton.image = configured
        }
        removeButton.contentTintColor = .secondaryLabelColor

        addSubview(imageView)
        addSubview(name)
        addSubview(removeHost)
        removeHost.addSubview(removeButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 32),
            imageView.heightAnchor.constraint(equalToConstant: 32),
            name.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
            name.trailingAnchor.constraint(equalTo: removeHost.leadingAnchor, constant: -6),
            name.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeHost.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            removeHost.centerYAnchor.constraint(equalTo: centerYAnchor),
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

    func configure(item: ImageEditsCatalogView.Item, thumb: NSImage?, appearance _: NSAppearance) {
        url = item.url
        imageView.image = thumb
        name.stringValue = item.url.lastPathComponent
        name.toolTip = item.url.path
        syncHoverFromWindow(animated: false)
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if !removeHost.isHidden, removeHost.alphaValue > 0.01, removeHost.frame.contains(local) {
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
        DispatchQueue.main.async { [weak self] in
            self?.syncHoverFromWindow(animated: true)
        }
    }

    private func syncHoverFromWindow(animated: Bool) {
        let loc = CatalogHoverPointer.location(in: self)
        let inside = loc.map { bounds.contains($0) } ?? false
        isHovered = inside
        let onTrash = loc.map { removeHost.frame.contains($0) } ?? false
        removeHost.setHovered(inside && onTrash, appearance: effectiveAppearance)
        removeButton.contentTintColor = (inside && onTrash) ? .labelColor : .secondaryLabelColor
        setHoverVisible(inside, animated: animated)
    }

    private func setHoverVisible(_ show: Bool, animated: Bool) {
        let apply = {
            self.removeHost.alphaValue = show ? 1 : 0
            self.removeHost.isHidden = !show
            self.layer?.backgroundColor = show
                ? LaughTheme.chromeHoverFill(appearance: self.effectiveAppearance).cgColor
                : NSColor.clear.cgColor
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
        if show {
            guard hoverMoveMonitor == nil else { return }
            hoverMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
                self?.syncHoverFromWindow(animated: false)
                return event
            }
        } else if let hoverMoveMonitor {
            NSEvent.removeMonitor(hoverMoveMonitor)
            self.hoverMoveMonitor = nil
        }
    }

    deinit {
        if let hoverMoveMonitor {
            NSEvent.removeMonitor(hoverMoveMonitor)
        }
    }

    @objc private func clearPressed() {
        guard let url else { return }
        onClear?(url)
    }
}
