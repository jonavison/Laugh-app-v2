import AppKit

/// What to show while Subject Select is busy: a line of text, plus a bar fraction when the
/// wait has honest progress to report.
///
/// Only the model download knows how far along it is. The select pipeline reports which
/// step it is on (`ImageSelectionSession.Stage`) rather than a percentage, so those states
/// narrate with a spinner instead of a bar that would have to invent its own movement.
struct SelectionBusyStatus: Equatable {
    let caption: String
    /// 0…1 for a determinate bar; `nil` for spinner-only.
    let fraction: Double?

    /// `nil` when the session is idle and the row should be hidden.
    static func make(phase: ImageSelectionSession.Phase) -> SelectionBusyStatus? {
        switch phase {
        case .idle:
            return nil
        case .downloading(let progress):
            let clamped = min(1, max(0, progress))
            let percent = Int((clamped * 100).rounded())
            return SelectionBusyStatus(
                caption: "Downloading MobileSAM… \(percent)%",
                fraction: clamped
            )
        case .selecting(let stage):
            return SelectionBusyStatus(caption: caption(for: stage), fraction: nil)
        }
    }

    private static func caption(for stage: ImageSelectionSession.Stage) -> String {
        switch stage {
        case .preparing:
            return "Preparing…"
        case .findingPeople:
            return "Finding people…"
        case .cuttingOut(let completed, let total):
            guard total > 1 else { return "Cutting out the subject…" }
            // `completed` counts finished people, so the one in flight is the next index.
            let current = min(completed + 1, total)
            return "Cutting out people (\(current) of \(total))…"
        case .refining:
            return "Refining edges…"
        }
    }
}

/// Spinner + status line for a long-running panel action, with a brand-teal bar for the
/// steps that report real progress. Deliberately not `NSProgressIndicator(style: .bar)`:
/// that one draws in the macOS accent colour (often system blue).
final class SelectionProgressView: NSView {
    private let spinner = NSProgressIndicator()
    private let captionLabel = NSTextField(labelWithString: "")
    private let bar = LaughProgressBarView()
    private var barHeightConstraint: NSLayoutConstraint!

    /// Nil hides the row and stops the spinner.
    var status: SelectionBusyStatus? {
        didSet {
            guard status != oldValue else { return }
            applyStatus()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false

        captionLabel.font = .systemFont(ofSize: 11, weight: .medium)
        captionLabel.textColor = .secondaryLabelColor
        captionLabel.lineBreakMode = .byTruncatingTail
        captionLabel.maximumNumberOfLines = 1
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let column = NSStackView(views: [captionLabel, bar])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 5
        column.translatesAutoresizingMaskIntoConstraints = false

        addSubview(spinner)
        addSubview(column)

        barHeightConstraint = bar.heightAnchor.constraint(equalToConstant: LaughProgressBarView.thickness)
        NSLayoutConstraint.activate([
            spinner.widthAnchor.constraint(equalToConstant: 14),
            spinner.heightAnchor.constraint(equalToConstant: 14),
            spinner.leadingAnchor.constraint(equalTo: leadingAnchor),
            spinner.centerYAnchor.constraint(equalTo: captionLabel.centerYAnchor),

            column.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),

            bar.leadingAnchor.constraint(equalTo: column.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: column.trailingAnchor),
            barHeightConstraint
        ])

        applyStatus()
    }

    private func applyStatus() {
        guard let status else {
            spinner.stopAnimation(nil)
            isHidden = true
            return
        }
        isHidden = false
        spinner.startAnimation(nil)
        captionLabel.stringValue = status.caption
        captionLabel.setAccessibilityLabel(status.caption)
        if let fraction = status.fraction {
            bar.isHidden = false
            barHeightConstraint.constant = LaughProgressBarView.thickness
            bar.fraction = fraction
        } else {
            bar.isHidden = true
            barHeightConstraint.constant = 0
        }
    }
}

/// Slim determinate bar in the LaughPlayer brand teal.
final class LaughProgressBarView: NSView {
    static let thickness: CGFloat = 4

    var fraction: Double = 0 {
        didSet {
            guard abs(fraction - oldValue) > 0.001 else { return }
            needsLayout = true
        }
    }

    private let trackLayer = CALayer()
    private let fillLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.thickness)
    }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.addSublayer(trackLayer)
        layer?.addSublayer(fillLayer)
        applyColors()
    }

    override func layout() {
        super.layout()
        let radius = bounds.height / 2
        trackLayer.frame = bounds
        trackLayer.cornerRadius = radius
        let width = bounds.width * CGFloat(min(1, max(0, fraction)))
        fillLayer.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        fillLayer.cornerRadius = radius
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    private func applyColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        trackLayer.backgroundColor = NSColor.labelColor
            .withAlphaComponent(isDark ? 0.16 : 0.10)
            .cgColor
        fillLayer.backgroundColor = LaughTheme.interactiveAccent.cgColor
    }
}
