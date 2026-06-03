import AppKit

/// LaughPlayer accent and selection colors (teal instead of system blue).
enum LaughTheme {
    private static let fallbackAccent = NSColor(
        calibratedRed: 0.16,
        green: 0.60,
        blue: 0.58,
        alpha: 1
    )

    static var accent: NSColor {
        NSColor(named: "AccentColor", bundle: .module) ?? fallbackAccent
    }

    /// Brighter teal for playback seek/volume (readable over dark video).
    static var playbackAccent: NSColor { sidebarSeparatorGradientStart }

    static var selectionBackground: NSColor { accent }

    /// Foreground on teal selection fills (recents list, queue).
    static var selectionText: NSColor { .white }

    /// Left library sidebar row highlight (neutral, not accent).
    static var sidebarSelectionBackground: NSColor {
        NSColor.labelColor.withAlphaComponent(0.11)
    }

    /// Tailwind teal-400 — start of sidebar Recents/Library divider gradient.
    static var sidebarSeparatorGradientStart: NSColor {
        NSColor(calibratedRed: 45 / 255, green: 212 / 255, blue: 191 / 255, alpha: 1)
    }

    /// Neutral gray — end of sidebar Recents/Library divider gradient.
    static var sidebarSeparatorGradientEnd: NSColor {
        NSColor.secondaryLabelColor.withAlphaComponent(0.65)
    }

    static var settingsTabIdle: NSColor { .secondaryLabelColor }

    static var settingsTabHover: NSColor {
        NSColor.labelColor.withAlphaComponent(0.78)
    }

    static var settingsTabActive: NSColor { .labelColor }

    static func activate() {
        _ = accent
    }

    /// Settings right panel: use Laugh teal instead of system blue on controls.
    static func applySettingsAccentChrome(to control: NSControl) {
        switch control {
        case let slider as NSSlider:
            applyContentTintColor(accent, to: slider)
            if !slider.isVertical {
                slider.useFlatBarAppearance(trackHeight: 3, filledColor: accent)
            }
        case let segmented as NSSegmentedControl:
            installTealSegmentedCell(on: segmented)
        case let button as NSButton:
            applySettingsButtonAccent(to: button)
        case let popUp as NSPopUpButton:
            popUp.contentTintColor = accent
        default:
            break
        }
    }

    /// Teal bezel on the active segment only (requires `.rounded` segment style).
    static func installTealSegmentedCell(on control: NSSegmentedControl) {
        control.selectedSegmentBezelColor = accent
        control.needsDisplay = true
    }

    private static func applySettingsButtonAccent(to button: NSButton) {
        if isSettingsCheckbox(button) {
            button.contentTintColor = accent
            applyCheckboxLabelStyle(to: button)
            return
        }
        if button.image != nil, button.title.isEmpty {
            button.contentTintColor = accent
        }
    }

    private static func isSettingsCheckbox(_ button: NSButton) -> Bool {
        guard button.image == nil, !button.isBordered else { return false }
        guard let cell = button.cell as? NSButtonCell else { return false }
        return cell.highlightsBy.rawValue == 1
    }

    /// Checkbox mark uses accent; title stays normal label color.
    static func applyCheckboxLabelStyle(to button: NSButton) {
        let title = button.title
        guard !title.isEmpty else { return }
        let font = button.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: NSColor.labelColor, .font: font]
        )
    }

    private static func applyContentTintColor(_ color: NSColor, to object: NSObject) {
        let selector = NSSelectorFromString("setContentTintColor:")
        guard object.responds(to: selector) else { return }
        object.perform(selector, with: color)
    }

    static func applySettingsAccentChrome(in view: NSView) {
        if let control = view as? NSControl {
            applySettingsAccentChrome(to: control)
        }
        for subview in view.subviews {
            applySettingsAccentChrome(in: subview)
        }
    }

    /// Backward-compatible name; settings chrome is accent-colored.
    static func applySettingsNeutralChrome(to control: NSControl) {
        applySettingsAccentChrome(to: control)
    }

    /// shadcn/ui Sidebar — https://ui.shadcn.com/docs/components/sidebar
    enum Sidebar {
        /// `SidebarMenu` — `flex flex-col gap-1`
        static let menuItemGap: CGFloat = 4

        /// `SidebarMenuButton` — `h-8 gap-2 rounded-md p-2 text-sm` + `[&>svg]:size-4`
        enum MenuButton {
            static let rowHeight: CGFloat = 32
            static let padding: CGFloat = 8
            static let gap: CGFloat = 8
            static let cornerRadius: CGFloat = 6
            static let fontSize: CGFloat = 13
            static let fontWeight: NSFont.Weight = .medium
            static let iconSize: CGFloat = 16
            static let edgeInset: CGFloat = 4

            static var labelFont: NSFont { .systemFont(ofSize: fontSize, weight: fontWeight) }

            static func symbolConfiguration() -> NSImage.SymbolConfiguration {
                NSImage.SymbolConfiguration(pointSize: iconSize, weight: fontWeight)
            }

            /// Highlight fills the full `h-8` row (padding is inside the pill).
            static func selectionRect(in bounds: NSRect) -> NSRect {
                bounds.insetBy(dx: edgeInset, dy: 0)
            }

            /// Main content recents list — same menu button, inset to match browse grid margins.
            enum ContentList {
                static let horizontalMargin: CGFloat = 16

                static func selectionRect(in bounds: NSRect) -> NSRect {
                    bounds.insetBy(dx: horizontalMargin, dy: 0)
                }

                static var contentLeadingInset: CGFloat { horizontalMargin + MenuButton.padding }
                static var contentTrailingInset: CGFloat { horizontalMargin + MenuButton.padding }
            }
        }

        /// `SidebarGroupLabel` — `h-8 px-2 text-xs font-medium` (section title, not a menu button).
        enum GroupLabel {
            static let rowHeight: CGFloat = 32
            static let paddingX: CGFloat = 8
            static let gap: CGFloat = 8
            static let fontSize: CGFloat = 11
            static let fontWeight: NSFont.Weight = .medium
            static let iconSize: CGFloat = 16

            static var labelFont: NSFont { .systemFont(ofSize: fontSize, weight: fontWeight) }

            static func symbolConfiguration() -> NSImage.SymbolConfiguration {
                NSImage.SymbolConfiguration(pointSize: iconSize, weight: fontWeight)
            }
        }

        /// `SidebarMenuSubButton` — `h-7 px-2 gap-2 text-sm` (nested under a group).
        enum MenuSubButton {
            static let rowHeight: CGFloat = 28
            static let paddingX: CGFloat = 8
            static let gap: CGFloat = 8
            static let cornerRadius: CGFloat = 6
            static let fontSize: CGFloat = 13
            static let fontWeight: NSFont.Weight = .regular
            static let iconSize: CGFloat = 16
            static let nestedLeadingExtra: CGFloat = 12
            static let edgeInset: CGFloat = 4

            static var contentLeadingInset: CGFloat { MenuButton.padding + nestedLeadingExtra }

            static var labelFont: NSFont { .systemFont(ofSize: fontSize, weight: fontWeight) }

            static func selectionRect(in bounds: NSRect) -> NSRect {
                bounds.insetBy(dx: edgeInset, dy: 0)
            }
        }
    }

    /// shadcn `Button` size `sm` for main-panel lists (teal accent rows).
    enum InlineButton {
        static let cornerRadius: CGFloat = 8
        static let fontSize: CGFloat = 13
        static let fontWeight: NSFont.Weight = .medium
        static let iconPointSize: CGFloat = 16
        static let iconSize: CGFloat = 16
        static let rowHeight: CGFloat = 32
        static let iconTextGap: CGFloat = 6
        static let textSidePadding: CGFloat = 10
        static let iconSidePadding: CGFloat = 8
        static let contentHeight: CGFloat = 16
        static let horizontalInset: CGFloat = 8
        static let intercellSpacing: CGFloat = 2
        static let listTopInset: CGFloat = 8

        static var verticalPadding: CGFloat { (rowHeight - contentHeight) / 2 }

        /// Icon at inline-start (`pl-2`); text side keeps `px-2.5`.
        static var contentLeadingInset: CGFloat { horizontalInset + iconSidePadding }

        static var contentTrailingInset: CGFloat { horizontalInset + textSidePadding }

        static var labelFont: NSFont { .systemFont(ofSize: fontSize, weight: fontWeight) }

        static func symbolConfiguration(weight: NSFont.Weight = fontWeight) -> NSImage.SymbolConfiguration {
            NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: weight)
        }

        static func selectionRect(in bounds: NSRect) -> NSRect {
            bounds.insetBy(dx: horizontalInset, dy: verticalPadding)
        }

    }

    static func fillSelection(in rect: NSRect, cornerRadius: CGFloat = InlineButton.cornerRadius, background: NSColor? = nil) {
        let path = NSBezierPath(
            roundedRect: rect,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        (background ?? selectionBackground).setFill()
        path.fill()
    }

    static func fillSidebarSelection(in rect: NSRect, cornerRadius: CGFloat = InlineButton.cornerRadius) {
        fillSelection(in: rect, cornerRadius: cornerRadius, background: sidebarSelectionBackground)
    }

    static func applySelectionLabelStyle(to label: NSTextField, selected: Bool, idleColor: NSColor) {
        label.textColor = selected ? selectionText : idleColor
    }

    static func applySidebarSelectionLabelStyle(to label: NSTextField, selected: Bool, idleColor: NSColor) {
        label.textColor = selected ? .labelColor : idleColor
    }
}
