import AppKit

/// Left docked column for **ImageMedia**: **Info** / **Edits** / **Batch** tabs (ADR 0006).
final class ImageInfoSidebarView: NSView {
    enum Tab: Int {
        case info = 0
        case edits = 1
        case batch = 2
    }

    var onTabChange: ((Tab) -> Void)?

    private let fillView = ImmersivePanelFillView()
    private let tabBar = ImageStudioRailTabBar()
    private let infoScrollView = NSScrollView()
    private let documentView = SettingsScrollDocumentView()
    private let contentStack = ImmersivePanelStackView()
    private let editsCatalog = ImageEditsCatalogView()
    private let batchCatalog = ImageBatchCatalogView()
    /// Trailing hairline — same `imageStudioSidebarEdgeBorder` as the edit column’s leading edge.
    private let trailingDivider = ImmersivePanelFillView()

    var editsView: ImageEditsCatalogView { editsCatalog }
    var batchView: ImageBatchCatalogView { batchCatalog }

    /// Immersive windows are movable by background — never drag the frame from Info.
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        fillView.translatesAutoresizingMaskIntoConstraints = false
        fillView.wantsLayer = true
        addSubview(fillView)

        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.onChange = { [weak self] tab in
            guard let self else { return }
            self.applyTabVisibility()
            self.onTabChange?(tab)
        }
        addSubview(tabBar)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = SettingsSectionStyle.sectionGap
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)

        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)

        infoScrollView.translatesAutoresizingMaskIntoConstraints = false
        infoScrollView.drawsBackground = false
        infoScrollView.borderType = .noBorder
        infoScrollView.hasVerticalScroller = true
        infoScrollView.hasHorizontalScroller = false
        infoScrollView.autohidesScrollers = true
        infoScrollView.scrollerStyle = .overlay
        infoScrollView.documentView = documentView
        addSubview(infoScrollView)

        editsCatalog.translatesAutoresizingMaskIntoConstraints = false
        editsCatalog.isHidden = true
        addSubview(editsCatalog)

        batchCatalog.translatesAutoresizingMaskIntoConstraints = false
        batchCatalog.isHidden = true
        addSubview(batchCatalog)

        trailingDivider.translatesAutoresizingMaskIntoConstraints = false
        trailingDivider.wantsLayer = true
        addSubview(trailingDivider, positioned: .above, relativeTo: fillView)

        NSLayoutConstraint.activate([
            fillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fillView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fillView.topAnchor.constraint(equalTo: topAnchor),
            fillView.bottomAnchor.constraint(equalTo: bottomAnchor),

            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            tabBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            tabBar.topAnchor.constraint(equalTo: topAnchor, constant: 12),

            infoScrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            infoScrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            infoScrollView.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 10),
            infoScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: infoScrollView.contentView.widthAnchor),

            editsCatalog.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            editsCatalog.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            editsCatalog.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 10),
            editsCatalog.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            batchCatalog.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            batchCatalog.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            batchCatalog.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 10),
            batchCatalog.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            trailingDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            trailingDivider.topAnchor.constraint(equalTo: topAnchor),
            trailingDivider.bottomAnchor.constraint(equalTo: bottomAnchor),
            trailingDivider.widthAnchor.constraint(equalToConstant: 1)
        ])

        applyStudioChromeBackground()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        syncDocumentWidth()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyStudioChromeBackground()
        tabBar.refreshChrome()
    }

    var selectedTab: Tab {
        tabBar.selectedTab
    }

    func selectTab(_ tab: Tab) {
        tabBar.select(tab, emit: false)
        applyTabVisibility()
    }

    /// Opaque studio floor — same solid fill as meta / carousel chrome.
    func applyStudioChromeBackground() {
        let appearance = effectiveAppearance
        let floor = LaughTheme.imageStudioFloorColor(appearance: appearance)
        fillView.layer?.backgroundColor = floor.cgColor
        layer?.backgroundColor = floor.cgColor
        trailingDivider.layer?.backgroundColor =
            LaughTheme.imageStudioSidebarEdgeBorder(appearance: appearance).cgColor
        addSubview(trailingDivider, positioned: .above, relativeTo: nil)
        tabBar.refreshChrome()
    }

    func configure(_ metadata: ImageFileMetadata) {
        contentStack.arrangedSubviews.forEach {
            contentStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        for (index, section) in metadata.sections.enumerated() {
            let block = makeStaticSection(section, accentIndex: index)
            contentStack.addArrangedSubview(block)
            block.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        layoutSubtreeIfNeeded()
        syncDocumentWidth()
        infoScrollView.contentView.scroll(to: .zero)
        infoScrollView.reflectScrolledClipView(infoScrollView.contentView)
    }

    func clear() {
        configure(ImageFileMetadata(sections: []))
    }

    private func applyTabVisibility() {
        infoScrollView.isHidden = selectedTab != .info
        editsCatalog.isHidden = selectedTab != .edits
        batchCatalog.isHidden = selectedTab != .batch
    }

    /// Always-open section: static header + card body (no chevron / collapse).
    private func makeStaticSection(_ section: ImageFileMetadata.Section, accentIndex: Int) -> NSView {
        let column = ImmersivePanelStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = SettingsSectionStyle.headerToCardSpacing
        column.translatesAutoresizingMaskIntoConstraints = false

        let accent = SettingsSectionStyle.rainbowAccent(at: accentIndex)
        let header = makeSectionHeader(
            title: section.title,
            symbolName: symbolName(for: section.title),
            accent: accent
        )
        column.addArrangedSubview(header)

        let card = SettingsSectionCard()
        card.usesEditsGlassFill = true
        for (rowIndex, row) in section.rows.enumerated() {
            let value = Self.makeValueLabel(row.value)
            let isLast = rowIndex == section.rows.count - 1
            card.addRow(SettingsRowFactory.valueRow(title: row.label, control: value), separatorBelow: !isLast)
        }
        card.setAccentTint(accent)
        column.addArrangedSubview(card)
        card.leadingAnchor.constraint(equalTo: column.leadingAnchor).isActive = true
        card.trailingAnchor.constraint(equalTo: column.trailingAnchor).isActive = true
        return column
    }

    private static let sectionHeaderIconSide: CGFloat = 18
    private static let sectionHeaderIconTitleGap: CGFloat = 6

    private func makeSectionHeader(title: String, symbolName: String, accent: NSColor) -> NSView {
        let headerIconPointSize: CGFloat = 13

        let chrome = ImmersivePanelFillView()
        chrome.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        icon.contentTintColor = accent
        if #available(macOS 11.0, *) {
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: headerIconPointSize, weight: .semibold)
            icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        }

        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byTruncatingTail

        let titleCluster = ImmersivePanelFillView()
        titleCluster.translatesAutoresizingMaskIntoConstraints = false
        titleCluster.addSubview(icon)
        titleCluster.addSubview(label)

        chrome.addSubview(titleCluster)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: Self.sectionHeaderIconSide),
            icon.heightAnchor.constraint(equalToConstant: Self.sectionHeaderIconSide),
            icon.leadingAnchor.constraint(equalTo: titleCluster.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: titleCluster.centerYAnchor),
            label.leadingAnchor.constraint(
                equalTo: icon.trailingAnchor,
                constant: Self.sectionHeaderIconTitleGap
            ),
            label.trailingAnchor.constraint(equalTo: titleCluster.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: icon.centerYAnchor, constant: 0.5),
            titleCluster.heightAnchor.constraint(equalToConstant: Self.sectionHeaderIconSide),

            titleCluster.leadingAnchor.constraint(equalTo: chrome.leadingAnchor),
            titleCluster.trailingAnchor.constraint(lessThanOrEqualTo: chrome.trailingAnchor),
            titleCluster.topAnchor.constraint(equalTo: chrome.topAnchor, constant: 5),
            titleCluster.bottomAnchor.constraint(equalTo: chrome.bottomAnchor, constant: -5),
            chrome.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])
        return chrome
    }

    private func syncDocumentWidth() {
        let width = infoScrollView.contentView.bounds.width
        guard width > 1 else { return }
        contentStack.layoutSubtreeIfNeeded()
        let height = max(contentStack.fittingSize.height, 1)
        documentView.setFrameSize(NSSize(width: width, height: height))
    }

    private func symbolName(for sectionTitle: String) -> String {
        switch sectionTitle {
        case "File": return "doc"
        case "Image": return "photo"
        case "Camera": return "camera"
        case "GPS": return "location"
        default: return "info.circle"
        }
    }

    private static func makeValueLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 2
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.toolTip = text
        return label
    }
}

// MARK: - Info / Edits / Batch tabs

final class ImageStudioRailTabBar: NSView {
    var onChange: ((ImageInfoSidebarView.Tab) -> Void)?
    private(set) var selectedTab: ImageInfoSidebarView.Tab = .info

    private let tabs: [ImageInfoSidebarView.Tab] = [.info, .edits, .batch]
    private let titles = ["Info", "Edits", "Batch"]
    private let track = NSView()
    /// One sliding pill — follows hover preview, settles on the selected tab.
    private let selectionPill = NSView()
    private let stack = NSStackView()
    private var buttons: [ImageStudioRailTabButton] = []
    private var pillLeading: NSLayoutConstraint?
    private var pillWidth: NSLayoutConstraint?
    private var hoveredTab: ImageInfoSidebarView.Tab?
    private let inset: CGFloat = 4
    private let pillCorner: CGFloat = 9

    /// Pill target: hover preview wins so the active chrome slides with the cursor.
    private var highlightedTab: ImageInfoSidebarView.Tab {
        hoveredTab ?? selectedTab
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        track.translatesAutoresizingMaskIntoConstraints = false
        track.wantsLayer = true
        track.layer?.cornerRadius = 12
        track.layer?.cornerCurve = .continuous
        track.layer?.masksToBounds = true
        addSubview(track)

        selectionPill.translatesAutoresizingMaskIntoConstraints = false
        selectionPill.wantsLayer = true
        selectionPill.layer?.cornerRadius = pillCorner
        selectionPill.layer?.cornerCurve = .continuous
        selectionPill.layer?.masksToBounds = true
        track.addSubview(selectionPill)

        stack.orientation = .horizontal
        stack.alignment = .height
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        track.addSubview(stack)

        for (index, tab) in tabs.enumerated() {
            let button = ImageStudioRailTabButton(title: titles[index], tab: tab)
            button.onHoverChange = { [weak self] tab, hovering in
                self?.handleTabHover(tab, hovering: hovering)
            }
            button.onPress = { [weak self] tab in
                self?.select(tab, emit: true)
            }
            buttons.append(button)
            stack.addArrangedSubview(button)
        }

        let leading = selectionPill.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: inset)
        let width = selectionPill.widthAnchor.constraint(equalToConstant: 80)
        pillLeading = leading
        pillWidth = width

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.topAnchor.constraint(equalTo: topAnchor),
            track.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: inset),
            stack.trailingAnchor.constraint(equalTo: track.trailingAnchor, constant: -inset),
            stack.topAnchor.constraint(equalTo: track.topAnchor, constant: inset),
            stack.bottomAnchor.constraint(equalTo: track.bottomAnchor, constant: -inset),
            leading,
            width,
            selectionPill.topAnchor.constraint(equalTo: track.topAnchor, constant: inset),
            selectionPill.bottomAnchor.constraint(equalTo: track.bottomAnchor, constant: -inset)
        ])
        refreshChrome()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func select(_ tab: ImageInfoSidebarView.Tab, emit: Bool) {
        selectedTab = tab
        hoveredTab = nil
        refreshChrome()
        refreshPill(animated: true)
        if emit {
            onChange?(tab)
        }
    }

    func refreshChrome() {
        let appearance = effectiveAppearance
        track.layer?.backgroundColor = LaughTheme.chromeHoverFill(appearance: appearance).cgColor
        selectionPill.layer?.backgroundColor = LaughTheme.chromeActiveFill(appearance: appearance).cgColor
        refreshTitles(appearance: appearance)
    }

    override func layout() {
        super.layout()
        refreshPill(animated: false)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshChrome()
    }

    private func handleTabHover(_ tab: ImageInfoSidebarView.Tab, hovering: Bool) {
        if hovering {
            hoveredTab = tab
        } else if hoveredTab == tab {
            hoveredTab = nil
        }
        refreshTitles(appearance: effectiveAppearance)
        refreshPill(animated: true)
    }

    private func refreshTitles(appearance: NSAppearance) {
        let active = highlightedTab
        for button in buttons {
            button.applyChrome(emphasized: button.tab == active, appearance: appearance)
        }
    }

    private func refreshPill(animated: Bool) {
        guard let index = tabs.firstIndex(of: highlightedTab) else { return }
        let count = CGFloat(tabs.count)
        guard count > 0, stack.bounds.width > 1 else { return }
        let cellWidth = stack.bounds.width / count
        let minX = stack.frame.minX + CGFloat(index) * cellWidth
        let apply = {
            self.pillLeading?.constant = minX
            self.pillWidth?.constant = cellWidth
        }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                apply()
                self.layoutSubtreeIfNeeded()
            }
        } else {
            apply()
        }
    }
}

/// Hit target + label only — chrome lives on the bar’s sliding pill.
private final class ImageStudioRailTabButton: NSView {
    let tab: ImageInfoSidebarView.Tab
    var onHoverChange: ((ImageInfoSidebarView.Tab, Bool) -> Void)?
    var onPress: ((ImageInfoSidebarView.Tab) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false {
        didSet {
            guard oldValue != isHovered else { return }
            onHoverChange?(tab, isHovered)
        }
    }
    private var mouseDownInside = false

    init(title: String, tab: ImageInfoSidebarView.Tab) {
        self.tab = tab
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        label.stringValue = title
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.lineBreakMode = .byClipping
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownInside = true
    }

    override func mouseDragged(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        mouseDownInside = bounds.contains(local)
    }

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let inside = mouseDownInside && bounds.contains(local)
        mouseDownInside = false
        guard inside else { return }
        onPress?(tab)
    }

    func applyChrome(emphasized: Bool, appearance: NSAppearance) {
        var color = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            color = emphasized ? NSColor.labelColor : NSColor.secondaryLabelColor
        }
        label.textColor = color
        label.font = NSFont.systemFont(ofSize: 13, weight: emphasized ? .semibold : .medium)
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
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }
}

