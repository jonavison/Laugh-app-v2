import AppKit
import QuartzCore

/// Soft edge strip marking the hover/click zone that opens a side panel.
/// Visual + cursor only — clicks stay coordinate-based so window resize still works.
final class EdgeHotZoneAffordanceView: NSView {
    enum Edge {
        case leading
        case trailing
    }

    var onActivate: (() -> Void)?

    /// Extra bottom clearance (e.g. open filmstrip + meta bar) so the soft end sits above chrome.
    var bottomContentInset: CGFloat = 0 {
        didSet {
            guard abs(oldValue - bottomContentInset) > 0.5 else { return }
            needsLayout = true
        }
    }

    /// Extra top clearance for title / toolbar chrome when needed.
    var topContentInset: CGFloat = 0 {
        didSet {
            guard abs(oldValue - topContentInset) > 0.5 else { return }
            needsLayout = true
        }
    }

    private let edge: Edge
    private let washLayer = CAGradientLayer()
    private let washMask = CAGradientLayer()
    private let rimLayer = CALayer()
    private var isShowing = false

    /// Keep the glow clear of window chrome / resize corners.
    private static let verticalInset: CGFloat = 22
    private static let stripCornerRadius: CGFloat = 11
    private static let rimWidth: CGFloat = 1.5

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        alphaValue = 0
        isHidden = true

        let noAnim: [String: CAAction] = [
            "opacity": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull(),
            "cornerRadius": NSNull()
        ]
        washLayer.actions = noAnim
        washMask.actions = noAnim
        rimLayer.actions = noAnim
        washLayer.mask = washMask
        washLayer.masksToBounds = true
        rimLayer.masksToBounds = true
        layer?.addSublayer(washLayer)
        layer?.addSublayer(rimLayer)
        applyChrome()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Let events pass through so resize / click-vs-drag monitors keep working.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        // Non-flipped: y=0 is the bottom of the window.
        let bottomInset = Self.verticalInset + max(0, bottomContentInset)
        let topInset = Self.verticalInset + max(0, topContentInset)
        let stripHeight = max(0, bounds.height - topInset - bottomInset)
        let strip = CGRect(x: 0, y: bottomInset, width: bounds.width, height: stripHeight)
        washLayer.frame = strip
        washLayer.cornerRadius = Self.stripCornerRadius

        // Soften top/bottom of the wash so it doesn’t read as a hard full-height rail.
        washMask.frame = washLayer.bounds
        washMask.startPoint = CGPoint(x: 0.5, y: 0)
        washMask.endPoint = CGPoint(x: 0.5, y: 1)
        washMask.colors = [
            NSColor.clear.cgColor,
            NSColor.white.cgColor,
            NSColor.white.cgColor,
            NSColor.clear.cgColor
        ]
        washMask.locations = [0, 0.14, 0.86, 1] as [NSNumber]

        let rimHeight = max(0, stripHeight - 8)
        let rimY = bottomInset + (stripHeight - rimHeight) / 2
        switch edge {
        case .leading:
            rimLayer.frame = CGRect(x: 0, y: rimY, width: Self.rimWidth, height: rimHeight)
        case .trailing:
            rimLayer.frame = CGRect(
                x: max(0, bounds.width - Self.rimWidth),
                y: rimY,
                width: Self.rimWidth,
                height: rimHeight
            )
        }
        rimLayer.cornerRadius = Self.rimWidth / 2
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyChrome()
    }

    func setVisible(_ visible: Bool, emphasized: Bool, animated: Bool) {
        _ = emphasized
        let targetAlpha: CGFloat = visible ? 1 : 0
        let show = visible

        let apply: () -> Void = { [weak self] in
            guard let self else { return }
            self.alphaValue = targetAlpha
            self.isHidden = !show
            self.isShowing = show
        }

        if animated, window != nil {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = show ? 0.18 : 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().alphaValue = targetAlpha
            } completionHandler: { [weak self] in
                guard let self else { return }
                self.isHidden = !show
                self.isShowing = show
            }
            if show { isHidden = false }
        } else {
            apply()
        }
        applyChrome()
        needsLayout = true
    }

    private func applyChrome() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Soft luminous wash — readable over video, never loud.
        let edgeColor = NSColor.white.withAlphaComponent(isDark ? 0.16 : 0.22)
        let midColor = NSColor.white.withAlphaComponent(isDark ? 0.06 : 0.08)
        let clear = NSColor.clear

        switch edge {
        case .leading:
            washLayer.startPoint = CGPoint(x: 0, y: 0.5)
            washLayer.endPoint = CGPoint(x: 1, y: 0.5)
        case .trailing:
            washLayer.startPoint = CGPoint(x: 1, y: 0.5)
            washLayer.endPoint = CGPoint(x: 0, y: 0.5)
        }
        washLayer.colors = [edgeColor.cgColor, midColor.cgColor, clear.cgColor]
        washLayer.locations = [0, 0.45, 1]

        rimLayer.backgroundColor = NSColor.white.withAlphaComponent(isDark ? 0.28 : 0.35).cgColor
    }
}
