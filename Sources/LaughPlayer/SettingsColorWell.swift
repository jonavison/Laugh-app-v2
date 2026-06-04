import AppKit

protocol SettingsColorWellInteractionDelegate: AnyObject {
    func colorWellDidBeginInteraction(_ colorWell: SettingsColorWell)
    func colorWellDidEndInteraction(_ colorWell: SettingsColorWell)
}

extension SettingsColorWellInteractionDelegate {
    func colorWellDidEndInteraction(_ colorWell: SettingsColorWell) {}
}

/// Plain color swatch (no NSColorWell “Button” label) that opens a compact palette popover.
final class SettingsColorWell: NSControl {
    weak var interactionDelegate: SettingsColorWellInteractionDelegate?
    var onColorChanged: (() -> Void)?
    /// When true, programmatic `color =` updates do not fire `onColorChanged`.
    var suppressNotifications = false

    private var colorPopover: NSPopover?
    private var storedColor: NSColor = .white

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 32).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
        applySwatchChrome()
        refreshSwatchFill()
    }

    var color: NSColor {
        get { storedColor }
        set {
            let prior = storedColor
            storedColor = newValue.usingColorSpace(.sRGB) ?? newValue
            refreshSwatchFill()
            if !suppressNotifications, !colorsEqual(prior, storedColor) {
                notifyColorChanged()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        interactionDelegate?.colorWellDidBeginInteraction(self)
        if let colorPopover, colorPopover.isShown {
            closeColorPopover()
            return
        }
        presentColorPopover()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applySwatchChrome()
    }

    private func applySwatchChrome() {
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    private func refreshSwatchFill() {
        layer?.backgroundColor = storedColor.cgColor
    }

    private func presentColorPopover() {
        let picker = SimpleColorOpacityPickerViewController(initialColor: storedColor) { [weak self] newColor in
            guard let self, !self.suppressNotifications else { return }
            self.applyPickedColor(newColor)
        }

        let popover = NSPopover()
        popover.contentViewController = picker
        _ = picker.view
        popover.contentSize = picker.view.frame.size
        popover.behavior = .semitransient
        popover.delegate = self
        popover.show(relativeTo: bounds, of: self, preferredEdge: .minX)
        colorPopover = popover
    }

    private func closeColorPopover() {
        colorPopover?.close()
        colorPopover = nil
        interactionDelegate?.colorWellDidEndInteraction(self)
    }

    private func applyPickedColor(_ newColor: NSColor) {
        let prior = storedColor
        storedColor = newColor.usingColorSpace(.sRGB) ?? newColor
        refreshSwatchFill()
        if !colorsEqual(prior, storedColor) {
            notifyColorChanged()
        }
    }

    private func notifyColorChanged() {
        onColorChanged?()
    }

    private func colorsEqual(_ lhs: NSColor, _ rhs: NSColor) -> Bool {
        let a = lhs.usingColorSpace(.sRGB) ?? lhs
        let b = rhs.usingColorSpace(.sRGB) ?? rhs
        return abs(a.redComponent - b.redComponent) < 0.001
            && abs(a.greenComponent - b.greenComponent) < 0.001
            && abs(a.blueComponent - b.blueComponent) < 0.001
            && abs(a.alphaComponent - b.alphaComponent) < 0.001
    }
}

extension SettingsColorWell: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        colorPopover = nil
        interactionDelegate?.colorWellDidEndInteraction(self)
    }
}
