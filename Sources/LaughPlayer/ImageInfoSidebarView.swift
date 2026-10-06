import AppKit

/// Left docked **ImageInfo** column: file + ImageIO metadata for the open still.
/// Flat always-open sections — no collapse / chevron chrome.
final class ImageInfoSidebarView: NSView {
    private let fillView = ImmersivePanelFillView()
    private let titleLabel = NSTextField(labelWithString: "Info")
    private let scrollView = NSScrollView()
    private let documentView = SettingsScrollDocumentView()
    private let contentStack = ImmersivePanelStackView()
    /// Trailing hairline — same `imageStudioSidebarEdgeBorder` as the edit column’s leading edge.
    private let trailingDivider = ImmersivePanelFillView()

    /// Immersive windows are movable by background — never drag the frame from Info.
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        fillView.translatesAutoresizingMaskIntoConstraints = false
        fillView.wantsLayer = true
        addSubview(fillView)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = SettingsSectionStyle.sectionGap
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)

        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = documentView
        addSubview(scrollView)

        trailingDivider.translatesAutoresizingMaskIntoConstraints = false
        trailingDivider.wantsLayer = true
        // Above fill — same stacking as the edit column’s leading hairline.
        addSubview(trailingDivider, positioned: .above, relativeTo: fillView)

        NSLayoutConstraint.activate([
            fillView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fillView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fillView.topAnchor.constraint(equalTo: topAnchor),
            fillView.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Centered page title — same horizontal inset as the scroll column.
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

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
    }

    /// Opaque studio floor — same solid fill as meta / carousel chrome.
    func applyStudioChromeBackground() {
        let appearance = effectiveAppearance
        let floor = LaughTheme.imageStudioFloorColor(appearance: appearance)
        fillView.layer?.backgroundColor = floor.cgColor
        layer?.backgroundColor = floor.cgColor
        trailingDivider.layer?.backgroundColor =
            LaughTheme.imageStudioSidebarEdgeBorder(appearance: appearance).cgColor
        // Keep hairline above content that may have been re-ordered.
        addSubview(trailingDivider, positioned: .above, relativeTo: nil)
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
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func clear() {
        configure(ImageFileMetadata(sections: []))
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
        // Flush with the header row — same leading edge as the icon (no stray indent).
        card.leadingAnchor.constraint(equalTo: column.leadingAnchor).isActive = true
        card.trailingAnchor.constraint(equalTo: column.trailingAnchor).isActive = true
        return column
    }

    private static let sectionHeaderIconSide: CGFloat = 18
    private static let sectionHeaderIconTitleGap: CGFloat = 6

    /// Match `CollapsibleSettingsSectionView` header chrome (Develop / Color / …) — no chevron.
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
            // Optical nudge: SF Symbols sit a hair high vs AppKit label bounds.
            label.centerYAnchor.constraint(equalTo: icon.centerYAnchor, constant: 0.5),
            titleCluster.heightAnchor.constraint(equalToConstant: Self.sectionHeaderIconSide),

            // Same leading edge as the card — no extra pad before the icon.
            titleCluster.leadingAnchor.constraint(equalTo: chrome.leadingAnchor),
            titleCluster.trailingAnchor.constraint(lessThanOrEqualTo: chrome.trailingAnchor),
            titleCluster.topAnchor.constraint(equalTo: chrome.topAnchor, constant: 5),
            titleCluster.bottomAnchor.constraint(equalTo: chrome.bottomAnchor, constant: -5),
            chrome.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])
        return chrome
    }

    private func syncDocumentWidth() {
        let width = scrollView.contentView.bounds.width
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
