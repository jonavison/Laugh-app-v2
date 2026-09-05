import AppKit

/// Top-level outline groups on the **Edits** tab (Luminar-style IA).
enum ImageDevelopGroupID: String, CaseIterable, Hashable {
    case essentials
    case landscape
    case creative
    case portrait
    case professional

    var title: String {
        switch self {
        case .essentials: return "Essentials"
        case .landscape: return "Landscape"
        case .creative: return "Creative"
        case .portrait: return "Portrait"
        case .professional: return "Professional"
        }
    }
}

/// One row under an outline group. `adjustSection` is set only for v1 expandable tools.
struct ImageDevelopToolDescriptor: Hashable {
    let id: String
    let title: String
    let symbolName: String
    /// When non-`nil`, the row expands into adjust controls for this section.
    let adjustSection: ImageAdjustSection?

    var isAvailable: Bool { adjustSection != nil }
}

/// Static catalog for the Edits outline. Unfinished tools stay listed as Coming soon.
enum ImageDevelopOutline {
    static let groups: [(ImageDevelopGroupID, [ImageDevelopToolDescriptor])] = [
        (.essentials, [
            .init(id: "develop", title: "Develop", symbolName: "sun.max.fill", adjustSection: .develop),
            .init(id: "erase", title: "Erase", symbolName: "eraser.fill", adjustSection: nil),
            .init(id: "structureAI", title: "Structure (AI)", symbolName: "square.3.layers.3d", adjustSection: nil),
            .init(id: "color", title: "Color", symbolName: "paintpalette.fill", adjustSection: .color),
            .init(id: "blackAndWhite", title: "Black & White", symbolName: "circle.lefthalf.filled", adjustSection: .blackAndWhite),
            .init(id: "details", title: "Details", symbolName: "wand.and.stars", adjustSection: .details),
            .init(id: "denoise", title: "Denoise", symbolName: "waveform", adjustSection: .denoise),
            .init(id: "vignette", title: "Vignette", symbolName: "circle.dashed", adjustSection: .vignette)
        ]),
        (.landscape, [
            .init(id: "sunrays", title: "Sunrays", symbolName: "sun.horizon.fill", adjustSection: .sunrays),
            .init(id: "twilight", title: "Twilight Enhancer (AI)", symbolName: "moon.stars.fill", adjustSection: nil),
            .init(id: "atmosphere", title: "Atmosphere (AI)", symbolName: "cloud.fog.fill", adjustSection: nil),
            .init(id: "landscape", title: "Landscape", symbolName: "mountain.2.fill", adjustSection: .landscape),
            .init(id: "water", title: "Water Enhancer (AI)", symbolName: "drop.fill", adjustSection: nil)
        ]),
        (.creative, [
            .init(id: "relight", title: "Relight (AI)", symbolName: "lightbulb.fill", adjustSection: nil),
            .init(id: "dramatic", title: "Dramatic", symbolName: "bolt.fill", adjustSection: .dramatic),
            .init(id: "mood", title: "Mood", symbolName: "paintbrush.pointed.fill", adjustSection: .mood),
            .init(id: "toning", title: "Toning", symbolName: "circle.hexagongrid.fill", adjustSection: .toning),
            .init(id: "matte", title: "Matte", symbolName: "rectangle.dashed", adjustSection: .matte),
            .init(id: "mystical", title: "Mystical", symbolName: "sparkles", adjustSection: .mystical),
            .init(id: "glow", title: "Glow", symbolName: "sparkle", adjustSection: .glow),
            .init(id: "blur", title: "Blur", symbolName: "camera.filters", adjustSection: .blur),
            .init(id: "filmGrain", title: "Film Grain", symbolName: "film", adjustSection: .filmGrain)
        ]),
        (.portrait, [
            .init(id: "portraitBokeh", title: "Portrait Bokeh (AI)", symbolName: "person.fill", adjustSection: nil),
            .init(id: "face", title: "Face (AI)", symbolName: "face.smiling", adjustSection: nil),
            .init(id: "skin", title: "Skin (AI)", symbolName: "hand.raised.fill", adjustSection: nil),
            .init(id: "body", title: "Body (AI)", symbolName: "figure.stand", adjustSection: nil),
            .init(id: "highKey", title: "High Key", symbolName: "sun.haze.fill", adjustSection: .highKey)
        ]),
        (.professional, [
            .init(id: "supercontrast", title: "Supercontrast", symbolName: "circle.righthalf.filled", adjustSection: .supercontrast),
            .init(id: "colorHarmony", title: "Color Harmony", symbolName: "paintpalette", adjustSection: .colorHarmony),
            .init(id: "dodgeBurn", title: "Dodge & Burn", symbolName: "paintbrush.pointed", adjustSection: .dodgeBurn),
            .init(id: "clone", title: "Clone", symbolName: "plus.viewfinder", adjustSection: nil)
        ])
    ]
}

/// Spacing for the Edits outline (group titles + tool rows).
enum ImageDevelopOutlineStyle {
    /// Gap under a group title before its first tool.
    static let titleToTools: CGFloat = 4
    /// Gap between expandable / Coming soon rows inside a group.
    static let toolRowSpacing: CGFloat = 8
    /// Gap between the last tool of one group and the next group title.
    static let groupSpacing: CGFloat = 16
    /// Trailing inset after the last outline tool so scroll content doesn’t hug the fade.
    static let bottomPadding: CGFloat = 12
}

/// Quiet group title between tool clusters on Edits.
final class ImageDevelopGroupHeaderView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = title.uppercased()
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// Non-expandable tool row for unfinished develop tools.
/// Matches the plain disclosure header look (no glass plate).
final class ImageDevelopComingSoonRowView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "Coming soon")

    init(title: String, symbolName: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let headerIconPointSize: CGFloat = 13
        let headerIconSide: CGFloat = 18

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .quaternaryLabelColor
        if #available(macOS 11.0, *) {
            iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: headerIconPointSize, weight: .semibold)
            iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        }
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: headerIconSide),
            iconView.heightAnchor.constraint(equalToConstant: headerIconSide)
        ])

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .quaternaryLabelColor
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        badgeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        badgeLabel.textColor = .quaternaryLabelColor
        badgeLabel.isEditable = false
        badgeLabel.isBordered = false
        badgeLabel.drawsBackground = false
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let titleCluster = NSView()
        titleCluster.translatesAutoresizingMaskIntoConstraints = false
        titleCluster.addSubview(iconView)
        titleCluster.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: titleCluster.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: titleCluster.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: titleCluster.trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor, constant: 0.5),
            titleCluster.heightAnchor.constraint(equalToConstant: headerIconSide)
        ])

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [titleCluster, spacer, badgeLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(title), Coming soon")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
