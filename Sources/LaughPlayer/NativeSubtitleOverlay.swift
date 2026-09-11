import AVFoundation
import AppKit

/// Renders legible subtitle text with user styling when AVPlayerLayer ignores `textStyleRules`.
@MainActor
final class NativeSubtitleOverlay: NSObject {
    private let legibleOutput = AVPlayerItemLegibleOutput()
    private let containerView = SubtitleOverlayContainerView()
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
    /// When false, ignore legible callbacks and hide text without detaching the output (avoids playback stalls).
    private var displaysSubtitles = false
    /// Only hide AVPlayer's renderer after the overlay has received subtitle text.
    private var suppressesPlayerSubtitleRendering = false
    private var sidecarCues: [SidecarSubtitleCue] = []
    /// Italic runs of the displayed text, from markup the source track left in the cue body.
    private var italicRanges: [NSRange] = []
    private var lastStyledContainerHeight: CGFloat = -1

    func install(in host: NSView) {
        guard hostView !== host else { return }
        hostView = host
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.onLayout = { [weak self] in
            self?.handleContainerLayout()
        }
        if containerView.superview !== host {
            host.addSubview(containerView, positioned: .above, relativeTo: nil)
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
        containerView.wantsLayer = true
        containerView.isHidden = true
    }

    func setSuppressedForAlternateBackend(_ suppressed: Bool) {
        if suppressed {
            detach()
            clearSidecar()
            containerView.isHidden = true
        } else {
            suppressesPlayerSubtitleRendering = false
            legibleOutput.suppressesPlayerRendering = false
        }
    }

    var usesSidecarPlayback: Bool { !sidecarCues.isEmpty }

    func loadSidecar(url: URL) {
        sidecarCues = SidecarSubtitleLoader.load(from: url)
        beginStyledCapture()
    }

    func clearSidecar() {
        sidecarCues = []
        clearDisplayedText()
    }

    func updateSidecar(at timeSec: Double, enabled: Bool, store: SettingsStore) {
        displaysSubtitles = enabled
        guard enabled, !sidecarCues.isEmpty else {
            if sidecarCues.isEmpty {
                clearDisplayedText()
            }
            return
        }
        let adjusted = timeSec + store.subtitleDelaySec
        let raw = SidecarSubtitleLoader.text(at: adjusted, in: sidecarCues)
        setDisplayedText(raw)
        applyVisualStyle(from: store)
        containerView.isHidden = textField.stringValue.isEmpty
        raiseAboveVideo()
    }

    func sync(item: AVPlayerItem?, enabled: Bool, store: SettingsStore) {
        displaysSubtitles = enabled
        guard enabled else {
            clearDisplayedText()
            legibleOutput.suppressesPlayerRendering = true
            return
        }
        if !sidecarCues.isEmpty {
            legibleOutput.suppressesPlayerRendering = true
            raiseAboveVideo()
            refreshAppearance(from: store)
            return
        }
        guard let item else {
            clearDisplayedText()
            return
        }

        if item.status == .readyToPlay {
            attach(to: item)
        } else if attachedItem !== item {
            return
        }

        raiseAboveVideo()
        refreshAppearance(from: store)
    }

    /// Applies current store styling to visible subtitle text (live slider / color updates).
    func refreshAppearance(from store: SettingsStore, userInitiated: Bool = false) {
        if userInitiated, attachedItem != nil {
            beginStyledCapture()
        }
        applyVisualStyle(from: store)
        if !textField.stringValue.isEmpty {
            containerView.isHidden = false
        }
    }

    var hasAttachedItem: Bool { attachedItem != nil }

    func applyVisualStyle(from store: SettingsStore) {
        let height = max(containerView.bounds.height, 1)
        let size = SubtitleAppearanceStyle.resolvedOverlayFontSize(
            fontSize: store.subtitleFontSize,
            scale: store.subtitleScale,
            containerHeight: height
        )
        let borderWidth = SubtitleAppearanceStyle.resolvedOverlayBorderWidth(
            borderWidth: store.subtitleBorderWidth,
            containerHeight: height
        )
        let font = SubtitleFont.nsFont(size: size)
        let fontColor = store.subtitleFontColor.usingColorSpace(.sRGB) ?? store.subtitleFontColor
        let borderColor = store.subtitleBorderColor.usingColorSpace(.sRGB) ?? store.subtitleBorderColor

        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: fontColor,
            .paragraphStyle: centeredParagraphStyle()
        ]
        if borderWidth > 0.25 {
            attrs[.strokeColor] = borderColor
            attrs[.strokeWidth] = -max(1, borderWidth)
        }
        if store.subtitleBackgroundEnabled {
            let bg = store.subtitleBackgroundColor.usingColorSpace(.sRGB) ?? store.subtitleBackgroundColor
            attrs[.backgroundColor] = bg
        }

        let plain = textField.stringValue
        if plain.isEmpty {
            textField.attributedStringValue = NSAttributedString()
        } else {
            let styled = NSMutableAttributedString(string: plain, attributes: attrs)
            let bounds = NSRange(location: 0, length: (plain as NSString).length)
            for range in italicRanges {
                let clamped = NSIntersectionRange(range, bounds)
                guard clamped.length > 0 else { continue }
                styled.addAttribute(.obliqueness, value: 0.2, range: clamped)
            }
            textField.attributedStringValue = styled
        }

        lastStyledContainerHeight = height
        updateVerticalPosition(userPosition: store.subtitlePosition)
    }

    /// Route legible text through this overlay instead of AVPlayerLayer (required for live styling).
    private func beginStyledCapture() {
        suppressesPlayerSubtitleRendering = true
        legibleOutput.suppressesPlayerRendering = true
    }

    private func raiseAboveVideo() {
        guard let host = hostView, containerView.superview === host else { return }
        host.addSubview(containerView, positioned: .above, relativeTo: nil)
    }

    func detach() {
        displaysSubtitles = false
        clearDisplayedText()
        clearSidecar()
        suppressesPlayerSubtitleRendering = false
        legibleOutput.suppressesPlayerRendering = false
        if let item = attachedItem {
            item.remove(legibleOutput)
        }
        attachedItem = nil
        legibleOutput.setDelegate(nil, queue: nil)
    }

    private func clearDisplayedText() {
        textField.stringValue = ""
        textField.attributedStringValue = NSAttributedString()
        italicRanges = []
        containerView.isHidden = true
    }

    /// Strips inline markup the source track left in the cue body before it can draw as text.
    private func setDisplayedText(_ raw: String) {
        let parsed = SubtitleMarkup.parse(raw)
        textField.stringValue = parsed.text
        italicRanges = parsed.italicRanges
    }

    private func attach(to item: AVPlayerItem) {
        if attachedItem === item, item.outputs.contains(where: { $0 === legibleOutput }) {
            legibleOutput.suppressesPlayerRendering = suppressesPlayerSubtitleRendering
            return
        }
        detach()
        legibleOutput.suppressesPlayerRendering = false
        legibleOutput.setDelegate(self, queue: .main)
        item.add(legibleOutput)
        attachedItem = item
    }

    private func handleContainerLayout() {
        guard displaysSubtitles, !textField.stringValue.isEmpty else { return }
        let height = containerView.bounds.height
        guard height > 1, abs(height - lastStyledContainerHeight) > 1 else { return }
        applyVisualStyle(from: SettingsStore.shared)
    }

    private func updateVerticalPosition(userPosition: Double) {
        topConstraint?.isActive = false
        centerYConstraint?.isActive = false

        let textHeight = max(
            textField.fittingSize.height,
            textField.intrinsicContentSize.height,
            ceil(textField.font?.pointSize ?? 36)
        )
        let height = max(containerView.bounds.height, 1)
        let inset = SubtitleAppearanceStyle.bottomInset(
            userPosition: userPosition,
            containerHeight: height,
            textHeight: textHeight,
            edgePadding: SubtitleAppearanceStyle.resolvedPositionEdgePadding(containerHeight: height)
        )
        bottomConstraint?.constant = -inset
        bottomConstraint?.isActive = true
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
            guard output === self.legibleOutput, self.displaysSubtitles, self.sidecarCues.isEmpty else { return }
            if !text.isEmpty {
                self.beginStyledCapture()
            }
            self.setDisplayedText(text)
            self.applyVisualStyle(from: SettingsStore.shared)
            self.containerView.isHidden = self.textField.stringValue.isEmpty
            self.raiseAboveVideo()
        }
    }
}

private final class SubtitleOverlayContainerView: NSView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
