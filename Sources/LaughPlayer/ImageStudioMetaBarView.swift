import AppKit

enum ImageStudioZoomMenuChoice {
    case fitScreen
    case percent(Int)
}

/// Thin chrome strip above the image folder carousel: favorite, stars, name, view toggles.
final class ImageStudioMetaBarView: NSView {
    var onFavoriteToggle: (() -> Void)?
    var onRatingChange: ((Int) -> Void)?
    var onZoomMenuChoice: ((ImageStudioZoomMenuChoice) -> Void)?
    var onCarouselVisibilityToggle: (() -> Void)?
    /// `true` = show original (before); `false` = show adjusted (after).
    var onBeforeAfterSelect: ((Bool) -> Void)?

    private let leadingStack = NSStackView()
    private let trailingStack = NSStackView()
    private let favoriteButton = NSButton(title: "", target: nil, action: nil)
    private let starButtons: [NSButton]
    private let nameLabel = NSTextField(labelWithString: "")
    private let fitPercentButton = NSButton(title: "Fit", target: nil, action: nil)
    private let carouselToggleButton = NSButton(title: "", target: nil, action: nil)
    private let beforeAfterControl = BeforeAfterSegmentControl()

    private var currentRating = 0
    private var isFitZoom = true
    private var currentZoomPercent = 100
    private var sizedButtons = Set<ObjectIdentifier>()

    private static let zoomPercents = [25, 50, 100, 200, 300, 600, 1200, 2400]

    override init(frame frameRect: NSRect) {
        starButtons = (1...5).map { _ in NSButton(title: "", target: nil, action: nil) }
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        configureChrome()
        configureLayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyStudioChromeBackground() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        needsDisplay = true
    }

    func configure(
        fileName: String,
        isFavorite: Bool,
        rating: Int,
        zoomPercent: Int,
        isFitZoom: Bool,
        carouselVisible: Bool,
        showingBefore: Bool
    ) {
        nameLabel.stringValue = fileName
        nameLabel.toolTip = fileName
        applyFavorite(isFavorite)
        applyRating(rating)
        self.isFitZoom = isFitZoom
        currentZoomPercent = max(1, zoomPercent)
        fitPercentButton.title = isFitZoom ? "Fit ▾" : "\(currentZoomPercent)% ▾"
        fitPercentButton.toolTip = "Zoom"
        applyCarouselVisible(carouselVisible)
        beforeAfterControl.setShowingBefore(showingBefore)
    }

    private func configureChrome() {
        styleIconButton(favoriteButton, symbol: "heart", label: "Favorite")
        favoriteButton.target = self
        favoriteButton.action = #selector(favoritePressed)

        for (index, button) in starButtons.enumerated() {
            styleIconButton(button, symbol: "star", label: "Rate \(index + 1)", pointSize: 14)
            button.tag = index + 1
            button.target = self
            button.action = #selector(starPressed(_:))
        }

        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        styleTextButton(fitPercentButton)
        fitPercentButton.target = self
        fitPercentButton.action = #selector(fitPercentPressed)

        styleCarouselToggleButton(visible: true)
        carouselToggleButton.target = self
        carouselToggleButton.action = #selector(carouselTogglePressed)

        beforeAfterControl.translatesAutoresizingMaskIntoConstraints = false
        beforeAfterControl.onSelect = { [weak self] showingBefore in
            self?.onBeforeAfterSelect?(showingBefore)
        }
    }

    private func configureLayout() {
        // True L | C | R: leading and trailing hug the edges; name is centered in the bar.
        leadingStack.orientation = .horizontal
        leadingStack.alignment = .centerY
        leadingStack.spacing = 2
        leadingStack.translatesAutoresizingMaskIntoConstraints = false
        leadingStack.addArrangedSubview(favoriteButton)
        starButtons.forEach { leadingStack.addArrangedSubview($0) }
        leadingStack.setContentHuggingPriority(.required, for: .horizontal)
        leadingStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        trailingStack.orientation = .horizontal
        trailingStack.alignment = .centerY
        trailingStack.spacing = 6
        trailingStack.translatesAutoresizingMaskIntoConstraints = false
        trailingStack.addArrangedSubview(fitPercentButton)
        trailingStack.addArrangedSubview(carouselToggleButton)
        trailingStack.addArrangedSubview(beforeAfterControl)
        trailingStack.setContentHuggingPriority(.required, for: .horizontal)
        trailingStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubview(nameLabel)
        addSubview(leadingStack)
        addSubview(trailingStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 38),

            leadingStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            leadingStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            trailingStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            trailingStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            nameLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            nameLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingStack.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingStack.leadingAnchor, constant: -10)
        ])
    }

    private func applyFavorite(_ favorite: Bool) {
        let symbol = favorite ? "heart.fill" : "heart"
        styleIconButton(favoriteButton, symbol: symbol, label: favorite ? "Remove favorite" : "Add favorite", pointSize: 15)
        favoriteButton.contentTintColor = favorite ? .systemPink : .secondaryLabelColor
    }

    private func applyRating(_ rating: Int) {
        currentRating = max(0, min(5, rating))
        for (index, button) in starButtons.enumerated() {
            let filled = index < currentRating
            styleIconButton(
                button,
                symbol: filled ? "star.fill" : "star",
                label: "Rate \(index + 1)",
                pointSize: 14
            )
            button.contentTintColor = filled ? .systemYellow : .tertiaryLabelColor
        }
    }

    private func applyCarouselVisible(_ visible: Bool) {
        styleCarouselToggleButton(visible: visible)
    }

    /// Filmstrip cue: clear frame + squares, stroke chevron above the row.
    private func styleCarouselToggleButton(visible: Bool) {
        carouselToggleButton.bezelStyle = .accessoryBarAction
        carouselToggleButton.isBordered = false
        carouselToggleButton.title = ""
        carouselToggleButton.toolTip = visible ? "Hide carousel" : "Show carousel"
        carouselToggleButton.imagePosition = .imageOnly
        carouselToggleButton.image = Self.carouselToggleImage(carouselVisible: visible)
        carouselToggleButton.contentTintColor = .secondaryLabelColor
        carouselToggleButton.translatesAutoresizingMaskIntoConstraints = false
        let id = ObjectIdentifier(carouselToggleButton)
        if !sizedButtons.contains(id) {
            sizedButtons.insert(id)
            NSLayoutConstraint.activate([
                carouselToggleButton.widthAnchor.constraint(equalToConstant: 26),
                carouselToggleButton.heightAnchor.constraint(equalToConstant: 26)
            ])
        }
    }

    /// Template glyph: outer frame, three clear squares on the bottom edge,
    /// and a stroke chevron in the open space above them.
    private static func carouselToggleImage(carouselVisible: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let outer = NSRect(x: 1.25, y: 1.25, width: rect.width - 2.5, height: rect.height - 2.5)
            let frame = NSBezierPath(roundedRect: outer, xRadius: 2.25, yRadius: 2.25)
            frame.lineWidth = 1.35
            NSColor.black.setStroke()
            frame.stroke()

            // Three thumbnail squares, sitting clearly on the bottom of the frame.
            let square: CGFloat = 3.0
            let gap: CGFloat = 1.5
            let count = 3
            let rowWidth = CGFloat(count) * square + CGFloat(count - 1) * gap
            var x = outer.midX - rowWidth / 2
            let squaresY = outer.minY + 2.0
            NSColor.black.setFill()
            for _ in 0..<count {
                let cell = NSRect(x: x, y: squaresY, width: square, height: square)
                NSBezierPath(roundedRect: cell, xRadius: 0.5, yRadius: 0.5).fill()
                x += square + gap
            }

            // Stroke chevron centered in the band above the squares (not overlapping them).
            let bandBottom = squaresY + square + 1.6
            let bandTop = outer.maxY - 2.0
            let midY = (bandBottom + bandTop) / 2
            let halfW: CGFloat = 3.0
            let halfH: CGFloat = 1.7
            let chevron = NSBezierPath()
            chevron.lineWidth = 1.35
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            if carouselVisible {
                // ⌄ hide
                chevron.move(to: NSPoint(x: outer.midX - halfW, y: midY + halfH))
                chevron.line(to: NSPoint(x: outer.midX, y: midY - halfH))
                chevron.line(to: NSPoint(x: outer.midX + halfW, y: midY + halfH))
            } else {
                // ⌃ show
                chevron.move(to: NSPoint(x: outer.midX - halfW, y: midY - halfH))
                chevron.line(to: NSPoint(x: outer.midX, y: midY + halfH))
                chevron.line(to: NSPoint(x: outer.midX + halfW, y: midY - halfH))
            }
            NSColor.black.setStroke()
            chevron.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    private func styleIconButton(_ button: NSButton, symbol: String, label: String, pointSize: CGFloat = 15) {
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.title = ""
        button.toolTip = label
        button.imagePosition = .imageOnly
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) {
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
            button.image?.isTemplate = true
        }
        button.contentTintColor = .secondaryLabelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        let id = ObjectIdentifier(button)
        if !sizedButtons.contains(id) {
            sizedButtons.insert(id)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 26),
                button.heightAnchor.constraint(equalToConstant: 26)
            ])
        }
    }

    private func styleTextButton(_ button: NSButton) {
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.font = .systemFont(ofSize: 13, weight: .semibold)
        button.contentTintColor = .secondaryLabelColor
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func makeZoomMenu() -> NSMenu {
        let menu = NSMenu()

        let fitItem = NSMenuItem(title: "Fit Screen", action: #selector(zoomMenuFitScreen), keyEquivalent: "")
        fitItem.target = self
        fitItem.state = isFitZoom ? .on : .off
        menu.addItem(fitItem)

        menu.addItem(.separator())

        for percent in Self.zoomPercents {
            let item = NSMenuItem(
                title: "\(percent)%",
                action: #selector(zoomMenuPercent(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = percent
            let matchesPercent = !isFitZoom && abs(currentZoomPercent - percent) <= 2
            item.state = matchesPercent ? .on : .off
            menu.addItem(item)
        }

        return menu
    }

    @objc private func favoritePressed() {
        onFavoriteToggle?()
    }

    @objc private func starPressed(_ sender: NSButton) {
        let value = sender.tag
        // Tap same star again clears rating.
        let next = (value == currentRating) ? 0 : value
        onRatingChange?(next)
    }

    @objc private func fitPercentPressed() {
        let menu = makeZoomMenu()
        let point = NSPoint(x: 0, y: fitPercentButton.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: fitPercentButton)
    }

    @objc private func zoomMenuFitScreen() {
        onZoomMenuChoice?(.fitScreen)
    }

    @objc private func zoomMenuPercent(_ sender: NSMenuItem) {
        onZoomMenuChoice?(.percent(sender.tag))
    }

    @objc private func carouselTogglePressed() {
        onCarouselVisibilityToggle?()
    }
}

/// Compact Before | After selector — both labels always visible; active is clearer, idle is dim.
private final class BeforeAfterSegmentControl: NSView {
    var onSelect: ((Bool) -> Void)?

    private let beforeButton = NSButton(title: "Before", target: nil, action: nil)
    private let afterButton = NSButton(title: "After", target: nil, action: nil)
    private let divider = NSTextField(labelWithString: "/")
    private var showingBefore = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        styleSegmentButton(beforeButton)
        beforeButton.toolTip = "Show original (before adjust)"
        beforeButton.target = self
        beforeButton.action = #selector(beforePressed)

        styleSegmentButton(afterButton)
        afterButton.toolTip = "Show adjusted image"
        afterButton.target = self
        afterButton.action = #selector(afterPressed)

        divider.font = .systemFont(ofSize: 13, weight: .regular)
        divider.textColor = .quaternaryLabelColor
        divider.alignment = .center
        divider.setContentHuggingPriority(.required, for: .horizontal)
        divider.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [beforeButton, divider, afterButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 26)
        ])

        setShowingBefore(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setShowingBefore(_ showingBefore: Bool) {
        self.showingBefore = showingBefore
        applySelectionChrome()
    }

    private func styleSegmentButton(_ button: NSButton) {
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func applySelectionChrome() {
        styleTitle(beforeButton, selected: showingBefore)
        styleTitle(afterButton, selected: !showingBefore)
    }

    private func styleTitle(_ button: NSButton, selected: Bool) {
        let weight: NSFont.Weight = selected ? .semibold : .regular
        let color: NSColor = selected ? .secondaryLabelColor : .tertiaryLabelColor
        let title = button.title
        let attributed = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: weight),
                .foregroundColor: color
            ]
        )
        button.attributedTitle = attributed
        button.contentTintColor = color
    }

    @objc private func beforePressed() {
        guard !showingBefore else { return }
        onSelect?(true)
    }

    @objc private func afterPressed() {
        guard showingBefore else { return }
        onSelect?(false)
    }
}
