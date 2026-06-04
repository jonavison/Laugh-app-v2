import AVFoundation
import AppKit

/// Renders legible subtitle text with user styling when AVPlayerLayer ignores `textStyleRules`.
@MainActor
final class NativeSubtitleOverlay: NSObject {
    private let legibleOutput = AVPlayerItemLegibleOutput()
    private let containerView = NSView()
    private let textField: NSTextField = {
        let field = NSTextField(labelWithString: "")
        field.alignment = .center
        field.lineBreakMode = .byWordWrapping
        field.maximumNumberOfLines = 0
        field.isBezeled = false
        field.isEditable = false
        field.isSelectable = false
        field.drawsBackground = false
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private weak var hostView: NSView?
    private weak var attachedItem: AVPlayerItem?
    private var bottomConstraint: NSLayoutConstraint?
    private var topConstraint: NSLayoutConstraint?
    private var centerYConstraint: NSLayoutConstraint?

    func install(in host: NSView) {
        guard hostView !== host else { return }
        hostView = host
        containerView.translatesAutoresizingMaskIntoConstraints = false
        if containerView.superview !== host {
            host.addSubview(containerView)
            NSLayoutConstraint.activate([
                containerView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                containerView.topAnchor.constraint(equalTo: host.topAnchor),
                containerView.bottomAnchor.constraint(equalTo: host.bottomAnchor)
            ])
        }
        if textField.superview !== containerView {
            containerView.addSubview(textField)
            let leading = textField.leadingAnchor.constraint(
                greaterThanOrEqualTo: containerView.leadingAnchor,
                constant: 32
            )
            let trailing = textField.trailingAnchor.constraint(
                lessThanOrEqualTo: containerView.trailingAnchor,
                constant: -32
            )
            leading.priority = .defaultHigh
            trailing.priority = .defaultHigh
            NSLayoutConstraint.activate([
                textField.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
                leading,
                trailing,
                textField.widthAnchor.constraint(lessThanOrEqualTo: containerView.widthAnchor, multiplier: 0.9)
            ])
            bottomConstraint = textField.bottomAnchor.constraint(
                equalTo: containerView.bottomAnchor,
                constant: -48
            )
            topConstraint = textField.topAnchor.constraint(
                equalTo: containerView.topAnchor,
                constant: 48
            )
            centerYConstraint = textField.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
            bottomConstraint?.isActive = true
        }
        containerView.isHidden = true
    }

    func setSuppressedForAlternateBackend(_ suppressed: Bool) {
        if suppressed {
            detach()
            containerView.isHidden = true
        }
    }

    func sync(item: AVPlayerItem?, enabled: Bool, store: SettingsStore) {
        guard !containerView.isHidden || enabled else {
            detach()
            return
        }
        guard enabled, let item, item.status == .readyToPlay else {
            detach()
            containerView.isHidden = true
            return
        }
        attach(to: item)
        applyVisualStyle(from: store)
        containerView.isHidden = false
    }

    func applyVisualStyle(from store: SettingsStore) {
        let size = max(12, store.subtitleFontSize * store.subtitleScale)
        let font = SubtitleFont.nsFont(size: size)
        let fontColor = store.subtitleFontColor.usingColorSpace(.sRGB) ?? store.subtitleFontColor
        let borderColor = store.subtitleBorderColor.usingColorSpace(.sRGB) ?? store.subtitleBorderColor

        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fontColor,
            .paragraphStyle: centeredParagraphStyle()
        ]
        if store.subtitleBorderWidth > 0.25 {
            attrs[.strokeColor] = borderColor
            attrs[.strokeWidth] = -max(1, store.subtitleBorderWidth)
        }
        if store.subtitleBackgroundEnabled {
            let bg = store.subtitleBackgroundColor.usingColorSpace(.sRGB) ?? store.subtitleBackgroundColor
            attrs[.backgroundColor] = bg
        }

        let plain = textField.stringValue
        if plain.isEmpty {
            textField.attributedStringValue = NSAttributedString()
        } else {
            textField.attributedStringValue = NSAttributedString(string: plain, attributes: attrs)
        }

        updateVerticalPosition(userPosition: store.subtitlePosition)
    }

    func detach() {
        textField.stringValue = ""
        textField.attributedStringValue = NSAttributedString()
        if let item = attachedItem {
            item.remove(legibleOutput)
        }
        attachedItem = nil
        legibleOutput.setDelegate(nil, queue: nil)
    }

    private func attach(to item: AVPlayerItem) {
        if attachedItem === item, item.outputs.contains(where: { $0 === legibleOutput }) {
            return
        }
        detach()
        legibleOutput.suppressesPlayerRendering = true
        legibleOutput.setDelegate(self, queue: .main)
        item.add(legibleOutput)
        attachedItem = item
    }

    private func updateVerticalPosition(userPosition: Double) {
        bottomConstraint?.isActive = false
        topConstraint?.isActive = false
        centerYConstraint?.isActive = false

        let clamped = max(
            SubtitleAppearanceStyle.positionMin,
            min(SubtitleAppearanceStyle.positionMax, userPosition)
        )
        if clamped <= 8 {
            bottomConstraint?.constant = -48
            bottomConstraint?.isActive = true
        } else if clamped >= 92 {
            topConstraint?.isActive = true
        } else {
            let t = (clamped - 50) / 50
            centerYConstraint?.constant = CGFloat(t * 120)
            centerYConstraint?.isActive = true
        }
        containerView.layoutSubtreeIfNeeded()
    }

    private func centeredParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byWordWrapping
        return style
    }
}

extension NativeSubtitleOverlay: AVPlayerItemLegibleOutputPushDelegate {
    nonisolated func legibleOutput(
        _ output: AVPlayerItemLegibleOutput,
        didOutputAttributedStrings strings: [NSAttributedString],
        nativeSampleBuffers: [Any],
        forItemTime itemTime: CMTime
    ) {
        let text = strings.map(\.string).filter { !$0.isEmpty }.joined(separator: "\n")
        Task { @MainActor in
            guard output === self.legibleOutput else { return }
            self.textField.stringValue = text
            self.applyVisualStyle(from: SettingsStore.shared)
            self.containerView.isHidden = text.isEmpty
        }
    }
}
