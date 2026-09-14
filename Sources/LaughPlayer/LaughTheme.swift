import AppKit

/// LaughPlayer accent and selection colors (teal brand — never system blue).
enum LaughTheme {
    private static let fallbackAccent = NSColor(
        calibratedRed: 0.16,
        green: 0.60,
        blue: 0.58,
        alpha: 1
    )

    /// Brand teal. Prefer this over `NSColor.controlAccentColor` / `.systemBlue`.
    static var accent: NSColor {
        NSColor(named: "AccentColor", bundle: ResourceBundle.bundle) ?? fallbackAccent
    }

    /// Alias for interactive brand fills (sliders, toggles, selected rings).
    /// Do **not** use `NSColor.controlAccentColor` — it follows the macOS accent
    /// preference (often blue) when Assets.car is missing.
    static var interactiveAccent: NSColor { accent }

    /// Grey bezel / chip fill for selected chrome (segments, tabs, tool active).
    /// Prefer this for active/hover chrome so UI never flashes system blue.
    static func chromeActiveFill(
        appearance: NSAppearance = NSApp.effectiveAppearance
    ) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor.labelColor.withAlphaComponent(isDark ? 0.32 : 0.18)
    }

    /// Quieter grey wash for hover-only chrome.
    static func chromeHoverFill(
        appearance: NSAppearance = NSApp.effectiveAppearance
    ) -> NSColor {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor.labelColor.withAlphaComponent(isDark ? 0.14 : 0.08)
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

    /// Left library sidebar plate — system window background (`windowBackgroundColor`).
    static func librarySidebarBackground(appearance: NSAppearance = NSApp.effectiveAppearance) -> NSColor {
        var base = NSColor.windowBackgroundColor
        appearance.performAsCurrentDrawingAppearance {
            base = NSColor.windowBackgroundColor
        }
        return base
    }

    /// Library browse/content pane — darker sibling of the sidebar (same tint, lower luminance).
    /// Darkens by blending the sidebar color toward black so hue stays in-family (slate-600 → slate-800, not zinc).
    static func libraryContentBackground(appearance: NSAppearance = NSApp.effectiveAppearance) -> NSColor {
        let base = librarySidebarBackground(appearance: appearance)
        guard let rgb = base.usingColorSpace(.deviceRGB) else {
            return base
        }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Near-neutral window grays: proportional RGB darkening keeps the same tint.
        if hue.isNaN || saturation < 0.04 {
            return blend(base, over: NSColor.black.withAlphaComponent(isDark ? 0.52 : 0.62))
        }
        let targetBrightness = isDark
            ? max(0.07, brightness * 0.50)
            : max(0.14, brightness * 0.42)
        return NSColor(calibratedHue: hue, saturation: saturation, brightness: targetBrightness, alpha: alpha)
    }

    /// Slightly lifted surface on the content pane (drop zones, inset panels).
    static func libraryContentRaisedBackground(appearance: NSAppearance = NSApp.effectiveAppearance) -> NSColor {
        let base = libraryContentBackground(appearance: appearance)
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let lift = NSColor.white.withAlphaComponent(isDark ? 0.06 : 0.10)
        return blend(base, over: lift)
    }

    /// Browse toolbar pills (Open, Play All, tabs, sort, search) — same plate as the left sidebar.
    static func libraryToolbarPillFill(appearance: NSAppearance = NSApp.effectiveAppearance) -> NSColor {
        librarySidebarBackground(appearance: appearance)
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

    /// Rainbow stops for selected image-studio tab icons (Edits / Presets).
    static var settingsTabIconRainbow: [NSColor] {
        [
            NSColor(calibratedHue: 0.02, saturation: 0.78, brightness: 0.95, alpha: 1),
            NSColor(calibratedHue: 0.12, saturation: 0.82, brightness: 0.95, alpha: 1),
            NSColor(calibratedHue: 0.33, saturation: 0.70, brightness: 0.88, alpha: 1),
            NSColor(calibratedHue: 0.55, saturation: 0.72, brightness: 0.95, alpha: 1),
            NSColor(calibratedHue: 0.72, saturation: 0.68, brightness: 0.95, alpha: 1),
            NSColor(calibratedHue: 0.88, saturation: 0.70, brightness: 0.95, alpha: 1)
        ]
    }

    /// Template SF Symbol filled with a diagonal rainbow gradient (non-template result).
    static func rainbowGradientSymbolImage(
        systemName: String,
        pointSize: CGFloat,
        weight: NSFont.Weight = .medium
    ) -> NSImage? {
        guard let base = NSImage(systemSymbolName: systemName, accessibilityDescription: nil) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = base.withSymbolConfiguration(config) else { return nil }

        let size = NSSize(
            width: max(1, ceil(symbol.size.width)),
            height: max(1, ceil(symbol.size.height))
        )
        let image = NSImage(size: size, flipped: false) { bounds in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.saveGState()
            symbol.draw(
                in: bounds,
                from: .zero,
                operation: .sourceOver,
                fraction: 1,
                respectFlipped: true,
                hints: nil
            )
            ctx.setBlendMode(.sourceIn)
            if let gradient = NSGradient(colors: settingsTabIconRainbow) {
                gradient.draw(in: bounds, angle: -45)
            }
            ctx.restoreGState()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Soft vertical teal wash for the left library sidebar (very low chroma).
    static func sidebarWashColors(
        appearance: NSAppearance = NSApp.effectiveAppearance
    ) -> (top: NSColor, bottom: NSColor) {
        var base = NSColor.windowBackgroundColor
        appearance.performAsCurrentDrawingAppearance {
            base = NSColor.windowBackgroundColor
        }
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let topWash = accent.withAlphaComponent(isDark ? 0.055 : 0.04)
        let bottomWash = accent.withAlphaComponent(isDark ? 0.016 : 0.012)
        return (
            top: blend(base, over: topWash),
            bottom: blend(base, over: bottomWash)
        )
    }

    static func imageStudioBackdropColors(
        appearance: NSAppearance = NSApp.effectiveAppearance
    ) -> (leading: NSColor, mid: NSColor, trailing: NSColor) {
        let base = imageStudioFloorColor(appearance: appearance)
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let accentWash = accent.withAlphaComponent(isDark ? 0.022 : 0.016)
        // Keep trailing at or below floor luminance — never bleach lighter than the real backdrop.
        let coolShift = (isDark
            ? NSColor.black.withAlphaComponent(0.035)
            : NSColor.black.withAlphaComponent(0.03))
        return (
            leading: blend(base, over: accentWash),
            mid: base,
            trailing: blend(base, over: coolShift)
        )
    }

    /// Flat studio floor currently painted by `DragHostView` in image mode (gradient layer is off).
    static func imageStudioFloorColor(
        appearance: NSAppearance = NSApp.effectiveAppearance
    ) -> NSColor {
        var base = NSColor.windowBackgroundColor
        appearance.performAsCurrentDrawingAppearance {
            base = NSColor.windowBackgroundColor
        }
        return base.usingColorSpace(.deviceRGB) ?? base
    }

    /// Translucent wash used by the edit column.
    static func imageStudioPanelWash(
        appearance: NSAppearance = NSApp.effectiveAppearance
    ) -> NSColor {
        var wash = NSColor.windowBackgroundColor.withAlphaComponent(0.82)
        appearance.performAsCurrentDrawingAppearance {
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            wash = NSColor.windowBackgroundColor.withAlphaComponent(isDark ? 0.78 : 0.88)
        }
        return wash
    }

    /// Opaque color matching how `imageStudioPanelWash` reads over the studio floor.
    /// Use on the floating tools bar so a bright photo underneath can’t lighten it.
    static func imageStudioPanelWashResolved(
        appearance: NSAppearance = NSApp.effectiveAppearance
    ) -> NSColor {
        let wash = imageStudioPanelWash(appearance: appearance)
        let floor = imageStudioFloorColor(appearance: appearance)
        guard let w = wash.usingColorSpace(.deviceRGB),
              let f = floor.usingColorSpace(.deviceRGB) else {
            return floor
        }
        var wr: CGFloat = 0, wg: CGFloat = 0, wb: CGFloat = 0, wa: CGFloat = 0
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        w.getRed(&wr, green: &wg, blue: &wb, alpha: &wa)
        f.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        let inv = 1 - wa
        return NSColor(
            calibratedRed: wr * wa + fr * inv,
            green: wg * wa + fg * inv,
            blue: wb * wa + fb * inv,
            alpha: 1
        )
    }

    /// Shared hairline for the edit column leading edge and image tools bar border.
    static func imageStudioChromeBorder(
        appearance: NSAppearance = NSApp.effectiveAppearance
    ) -> NSColor {
        var color = NSColor.separatorColor
        appearance.performAsCurrentDrawingAppearance {
            color = NSColor.separatorColor
        }
        return color
    }

    /// Color of the studio diagonal at a unit point in layer space (origin bottom-leading, matching `CAGradientLayer`).
    /// Gradient axis matches DragHost: top-leading → bottom-trailing (`start (0,1)` → `end (1,0)`).
    static func imageStudioBackdropColor(
        atUnitPoint unit: CGPoint,
        appearance: NSAppearance = NSApp.effectiveAppearance
    ) -> NSColor {
        // Studio currently paints a flat floor — edge fades must match that, not a lighter wash.
        _ = unit
        return imageStudioFloorColor(appearance: appearance)
    }

    private static func mix(_ a: NSColor, _ b: NSColor, amount: CGFloat) -> NSColor {
        let t = min(1, max(0, amount))
        let ca = a.usingColorSpace(.deviceRGB) ?? a
        let cb = b.usingColorSpace(.deviceRGB) ?? b
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ca.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        cb.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return NSColor(
            calibratedRed: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t,
            alpha: 1
        )
    }

    static func blend(_ base: NSColor, over tint: NSColor) -> NSColor {
        let b = base.usingColorSpace(.deviceRGB) ?? base
        let t = tint.usingColorSpace(.deviceRGB) ?? tint
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        t.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        let a = ta
        return NSColor(
            calibratedRed: br * (1 - a) + tr * a,
            green: bg * (1 - a) + tg * a,
            blue: bb * (1 - a) + tb * a,
            alpha: 1
        )
    }

    static func activate() {
        _ = accent
    }

    /// Settings right panel: tint controls with Laugh teal (or a custom section accent).
    static func applySettingsAccentChrome(to control: NSControl, accent color: NSColor = accent) {
        switch control {
        case let slider as NSSlider:
            applyContentTintColor(color, to: slider)
            if !slider.isVertical {
                if let flat = slider.flatBarCell {
                    flat.filledColor = color
                    flat.showsKnob = true
                    slider.needsDisplay = true
                } else {
                    slider.useFlatBarAppearance(trackHeight: 3, filledColor: color, showsKnob: true)
                }
            }
        case let segmented as NSSegmentedControl:
            installChromeSegmentSelection(on: segmented)
        case let button as NSButton:
            applySettingsButtonAccent(to: button, accent: color)
        case let popUp as NSPopUpButton:
            // Neutral — system popup tint often reads as blue without Assets.car.
            popUp.contentTintColor = .labelColor
        default:
            break
        }
    }

    /// Grey selected bezel for segmented controls (never system blue / loud teal).
    static func installChromeSegmentSelection(on control: NSSegmentedControl) {
        control.selectedSegmentBezelColor = chromeActiveFill(appearance: control.effectiveAppearance)
        control.needsDisplay = true
    }

    /// - Warning: Prefer `installChromeSegmentSelection` for chrome. Kept for call-site compat.
    static func installTealSegmentedCell(on control: NSSegmentedControl, accent color: NSColor = accent) {
        _ = color
        installChromeSegmentSelection(on: control)
    }

    private static func applySettingsButtonAccent(to button: NSButton, accent color: NSColor = accent) {
        if isSettingsCheckbox(button) {
            button.contentTintColor = color
            applyCheckboxLabelStyle(to: button)
            return
        }
        if button.image != nil, button.title.isEmpty {
            button.contentTintColor = color
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

    static func applySettingsAccentChrome(in view: NSView, accent color: NSColor = accent) {
        // Section cards own a rainbow tint — refresh from the card, don't paint panel teal.
        if let card = view as? SettingsSectionCard {
            card.applyControlAccentChrome()
            return
        }
        if let control = view as? NSControl {
            applySettingsAccentChrome(to: control, accent: color)
        }
        for subview in view.subviews {
            applySettingsAccentChrome(in: subview, accent: color)
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

        /// Vertical space around the Library section rule.
        static let sectionSeparatorHeight: CGFloat = 22

        /// `SidebarMenuButton` — `h-8 gap-2 rounded-md p-2 text-sm` + `[&>svg]:size-4`
        enum MenuButton {
            static let rowHeight: CGFloat = 32
            static let padding: CGFloat = 12
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
            /// Indent nested rows so labels align with section header labels (icon + gap).
            static let nestedLeadingExtra: CGFloat = MenuButton.iconSize + MenuButton.gap
            static let edgeInset: CGFloat = 4

            static var contentLeadingInset: CGFloat { MenuButton.padding + nestedLeadingExtra }

            static var labelFont: NSFont { .systemFont(ofSize: fontSize, weight: fontWeight) }

            static func symbolConfiguration() -> NSImage.SymbolConfiguration {
                NSImage.SymbolConfiguration(pointSize: iconSize, weight: fontWeight)
            }

            static func selectionRect(in bounds: NSRect) -> NSRect {
                bounds.insetBy(dx: edgeInset, dy: 0)
            }
        }

        static func mediaKindSymbol(for kind: DroppedMediaKind) -> String {
            kind == .video ? "film" : "photo"
        }

        /// Colored tint for top-level section headers only (Recents, Favorites, Library).
        static func iconColor(forSymbol symbol: String, appearance: NSAppearance = NSApp.effectiveAppearance) -> NSColor {
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let sat: CGFloat = isDark ? 0.62 : 0.68
            let bri: CGFloat = isDark ? 0.90 : 0.82
            switch symbol {
            case "clock.fill":
                return NSColor(calibratedHue: 0.08, saturation: sat, brightness: bri, alpha: 1)
            case "heart.fill":
                return NSColor(calibratedHue: 0.97, saturation: sat * 0.9, brightness: min(1, bri + 0.06), alpha: 1)
            case "folder.fill":
                return accent
            default:
                return accent
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
