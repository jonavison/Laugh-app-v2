import AppKit

/// Compact swatch grid + opacity (no RGB sliders or system color picker).
final class SimpleColorOpacityPickerViewController: NSViewController {
    var onColorChanged: ((NSColor) -> Void)?

    private static let columns = 8
    private static let swatchSize: CGFloat = 20
    private static let swatchGap: CGFloat = 4

    /// Subtitle-friendly palette (sRGB, opaque bases).
    private static let palette: [(CGFloat, CGFloat, CGFloat)] = [
        (1.00, 1.00, 1.00), (0.92, 0.92, 0.92), (0.78, 0.78, 0.78), (0.55, 0.55, 0.55),
        (0.35, 0.35, 0.35), (0.18, 0.18, 0.18), (0.08, 0.08, 0.08), (0.00, 0.00, 0.00),
        (1.00, 0.95, 0.55), (1.00, 0.85, 0.20), (1.00, 0.65, 0.10), (1.00, 0.45, 0.15),
        (1.00, 0.25, 0.20), (0.95, 0.55, 0.65), (0.90, 0.35, 0.55), (0.75, 0.20, 0.45),
        (0.55, 1.00, 0.45), (0.30, 0.90, 0.35), (0.20, 0.75, 0.55), (0.25, 0.85, 0.85),
        (0.35, 0.75, 1.00), (0.25, 0.50, 1.00), (0.45, 0.35, 0.95), (0.65, 0.35, 1.00),
        (0.85, 0.75, 1.00), (0.70, 0.55, 0.95), (0.55, 0.40, 0.80), (0.40, 0.28, 0.62),
        (0.95, 0.90, 0.80), (0.85, 0.72, 0.55), (0.70, 0.55, 0.40), (0.55, 0.42, 0.30),
        (0.40, 0.30, 0.22), (0.28, 0.22, 0.18), (0.18, 0.14, 0.12), (0.10, 0.08, 0.07)
    ]

    private let preview = NSView()
    private let alphaSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private var swatchButtons: [ColorSwatchButton] = []
    private var selectedSwatchIndex = 0
    private var alphaValue: CGFloat = 1

    init(initialColor: NSColor, onColorChanged: @escaping (NSColor) -> Void) {
        self.onColorChanged = onColorChanged
        super.init(nibName: nil, bundle: nil)
        let rgb = initialColor.usingColorSpace(.sRGB) ?? initialColor
        alphaValue = rgb.alphaComponent
        selectedSwatchIndex = Self.nearestPaletteIndex(to: rgb)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let gridWidth = CGFloat(Self.columns) * Self.swatchSize
            + CGFloat(Self.columns - 1) * Self.swatchGap
        let rowCount = (Self.palette.count + Self.columns - 1) / Self.columns
        let gridHeight = CGFloat(rowCount) * Self.swatchSize
            + CGFloat(max(0, rowCount - 1)) * Self.swatchGap
        let width = gridWidth + 20
        let height = 18 + 8 + gridHeight + 10 + 24 + 16
        view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        preview.wantsLayer = true
        preview.layer?.cornerRadius = 4
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = NSColor.separatorColor.cgColor

        alphaSlider.controlSize = .small
        alphaSlider.isContinuous = true
        alphaSlider.doubleValue = alphaValue
        alphaSlider.target = self
        alphaSlider.action = #selector(alphaChanged(_:))

        let opacityLabel = NSTextField(labelWithString: "Opacity")
        opacityLabel.font = .systemFont(ofSize: 11)
        opacityLabel.textColor = .secondaryLabelColor

        let opacityRow = NSStackView(views: [opacityLabel, alphaSlider])
        opacityRow.orientation = .horizontal
        opacityRow.spacing = 8
        opacityRow.alignment = .centerY
        alphaSlider.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let swatchGrid = buildSwatchGrid()
        let stack = NSStackView(views: [preview, swatchGrid, opacityRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            preview.widthAnchor.constraint(equalTo: stack.widthAnchor),
            preview.heightAnchor.constraint(equalToConstant: 18),
            swatchGrid.widthAnchor.constraint(equalToConstant: gridWidth),
            opacityRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        updateSelectionHighlight()
        refreshPreview()
    }

    private func buildSwatchGrid() -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.spacing = Self.swatchGap
        container.alignment = .leading

        var index = 0
        while index < Self.palette.count {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = Self.swatchGap
            row.alignment = .centerY
            for _ in 0..<Self.columns where index < Self.palette.count {
                let rgb = Self.palette[index]
                let button = ColorSwatchButton(
                    color: NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1),
                    size: Self.swatchSize
                )
                button.tag = index
                button.target = self
                button.action = #selector(swatchPressed(_:))
                swatchButtons.append(button)
                row.addArrangedSubview(button)
                index += 1
            }
            container.addArrangedSubview(row)
        }
        return container
    }

    @objc private func swatchPressed(_ sender: ColorSwatchButton) {
        selectedSwatchIndex = sender.tag
        updateSelectionHighlight()
        refreshPreview()
        onColorChanged?(currentColor())
    }

    @objc private func alphaChanged(_ sender: NSSlider) {
        alphaValue = CGFloat(sender.doubleValue)
        refreshPreview()
        onColorChanged?(currentColor())
    }

    private func updateSelectionHighlight() {
        for button in swatchButtons {
            button.isChosen = button.tag == selectedSwatchIndex
        }
    }

    private func currentColor() -> NSColor {
        let rgb = Self.palette[selectedSwatchIndex]
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: alphaValue)
    }

    private func refreshPreview() {
        preview.layer?.backgroundColor = currentColor().cgColor
    }

    private static func nearestPaletteIndex(to color: NSColor) -> Int {
        let c = color.usingColorSpace(.sRGB) ?? color
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, rgb) in palette.enumerated() {
            let dr = Double(c.redComponent - rgb.0)
            let dg = Double(c.greenComponent - rgb.1)
            let db = Double(c.blueComponent - rgb.2)
            let distance = dr * dr + dg * dg + db * db
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }
}

// MARK: - Swatch cell

private final class ColorSwatchButton: NSButton {
    private let swatchColor: NSColor

    var isChosen = false {
        didSet { needsDisplay = true }
    }

    init(color: NSColor, size: CGFloat) {
        swatchColor = color
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        isBordered = false
        bezelStyle = .inline
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true
        layer?.backgroundColor = color.cgColor
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isChosen {
            let inset: CGFloat = 1.5
            let ring = bounds.insetBy(dx: inset, dy: inset)
            let path = NSBezierPath(roundedRect: ring, xRadius: 3, yRadius: 3)
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
}
