import AppKit

/// Floating bottom chrome for **ImageSlideshow** (prev / play-pause / next / interval / exit).
final class ImageSlideshowControlsView: NSVisualEffectView {
    var onPrevious: (() -> Void)?
    var onTogglePlayPause: (() -> Void)?
    var onNext: (() -> Void)?
    var onIntervalChange: ((TimeInterval) -> Void)?
    var onExit: (() -> Void)?
    var onUserActivity: (() -> Void)?

    private let stack = NSStackView()
    private let captionLabel = NSTextField(labelWithString: "")
    private let previousButton = MusicStylePlaybackBar.iconButton(
        symbolName: "backward.fill",
        accessibilityLabel: "Previous",
        pointSize: 14
    )
    private let playPauseButton = MusicStylePlaybackBar.playPauseButton(
        pointSize: MusicStylePlaybackBar.playPauseIconPointSize
    )
    private let nextButton = MusicStylePlaybackBar.iconButton(
        symbolName: "forward.fill",
        accessibilityLabel: "Next",
        pointSize: 14
    )
    private let intervalControl = NSSegmentedControl(
        labels: ["2s", "4s", "8s"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let exitButton = MusicStylePlaybackBar.iconButton(
        symbolName: "xmark",
        accessibilityLabel: "Exit",
        pointSize: 13
    )

    private static let intervalOptions: [TimeInterval] = [2, 4, 8]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        MusicStylePlaybackBar.applyChrome(to: self)

        captionLabel.font = .systemFont(ofSize: 12, weight: .medium)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.lineBreakMode = .byTruncatingMiddle
        captionLabel.alignment = .center
        captionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        intervalControl.segmentStyle = .rounded
        intervalControl.focusRingType = .none
        intervalControl.target = self
        intervalControl.action = #selector(intervalChanged)
        LaughTheme.installChromeSegmentSelection(on: intervalControl)
        intervalControl.setContentHuggingPriority(.required, for: .horizontal)

        previousButton.target = self
        previousButton.action = #selector(previousPressed)
        playPauseButton.target = self
        playPauseButton.action = #selector(playPausePressed)
        nextButton.target = self
        nextButton.action = #selector(nextPressed)
        exitButton.target = self
        exitButton.action = #selector(exitPressed)

        for button in [previousButton, playPauseButton, nextButton, exitButton] {
            button.focusRingType = .none
        }

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(previousButton)
        stack.addArrangedSubview(playPauseButton)
        stack.addArrangedSubview(nextButton)
        stack.addArrangedSubview(intervalControl)
        stack.addArrangedSubview(captionLabel)
        stack.addArrangedSubview(exitButton)
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 52),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: MusicStylePlaybackBar.controlSize),
            previousButton.heightAnchor.constraint(equalToConstant: MusicStylePlaybackBar.controlSize),
            playPauseButton.widthAnchor.constraint(equalToConstant: MusicStylePlaybackBar.controlSize),
            playPauseButton.heightAnchor.constraint(equalToConstant: MusicStylePlaybackBar.controlSize),
            nextButton.widthAnchor.constraint(equalToConstant: MusicStylePlaybackBar.controlSize),
            nextButton.heightAnchor.constraint(equalToConstant: MusicStylePlaybackBar.controlSize),
            exitButton.widthAnchor.constraint(equalToConstant: MusicStylePlaybackBar.controlSize),
            exitButton.heightAnchor.constraint(equalToConstant: MusicStylePlaybackBar.controlSize),
            intervalControl.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        ])
        stack.setCustomSpacing(14, after: nextButton)
        stack.setCustomSpacing(16, after: intervalControl)
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        captionLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        MusicStylePlaybackBar.syncRoundedShape(for: self)
    }

    /// When faded out, pass clicks through so ←/→ browsing isn’t blocked by an invisible bar.
    override func hitTest(_ point: NSPoint) -> NSView? {
        alphaValue < 0.05 ? nil : super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        onUserActivity?()
        super.mouseDown(with: event)
    }

    func configure(playing: Bool, interval: TimeInterval, caption: String) {
        updatePlayPauseSymbol(playing: playing)
        selectInterval(interval)
        captionLabel.stringValue = caption
        LaughTheme.installChromeSegmentSelection(on: intervalControl)
    }

    func updatePlayPauseSymbol(playing: Bool) {
        let symbol = playing ? "pause.fill" : "play.fill"
        let label = playing ? "Pause" : "Play"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) {
            let config = NSImage.SymbolConfiguration(
                pointSize: MusicStylePlaybackBar.playPauseIconPointSize,
                weight: .medium
            )
            playPauseButton.image = image.withSymbolConfiguration(config)
            playPauseButton.image?.isTemplate = true
        }
        playPauseButton.toolTip = label
        playPauseButton.setAccessibilityLabel(label)
    }

    private func selectInterval(_ interval: TimeInterval) {
        let index = Self.intervalOptions.firstIndex(of: interval)
            ?? Self.intervalOptions.firstIndex(of: 4)
            ?? 1
        intervalControl.selectedSegment = index
    }

    @objc private func previousPressed() {
        onUserActivity?()
        onPrevious?()
    }

    @objc private func playPausePressed() {
        onUserActivity?()
        onTogglePlayPause?()
    }

    @objc private func nextPressed() {
        onUserActivity?()
        onNext?()
    }

    @objc private func exitPressed() {
        onUserActivity?()
        onExit?()
    }

    @objc private func intervalChanged() {
        onUserActivity?()
        let index = max(0, min(Self.intervalOptions.count - 1, intervalControl.selectedSegment))
        onIntervalChange?(Self.intervalOptions[index])
        LaughTheme.installChromeSegmentSelection(on: intervalControl)
    }
}
