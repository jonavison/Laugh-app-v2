import AppKit

/// Subtitles tab widgets (tracks, timing, placement, text style).
final class SubtitlesSettingsControls {
    let primaryEnabledSwitch = CompactTealToggle()
    let primaryTrackPopUp = NSPopUpButton()
    let secondaryEnabledSwitch = CompactTealToggle()
    let secondaryTrackPopUp = NSPopUpButton()
    let loadExternalButton = NSButton(title: "Load file…", target: nil, action: nil)
    let externalFileLabel = NSTextField(labelWithString: "No external file")
    let companionFilesLabel = NSTextField(labelWithString: "")
    let extendedPlaybackButton = NSButton(title: "Use extended playback for subtitles", target: nil, action: nil)
    let extendedOnlyLabel = NSTextField(labelWithString: "")

    let delaySlider = NSSlider(value: 0, minValue: SubtitleAppearanceStyle.delayMin, maxValue: SubtitleAppearanceStyle.delayMax, target: nil, action: nil)
    let delayValueLabel = NSTextField(labelWithString: "0.0 s")
    let positionSlider = NSSlider(value: 0, minValue: SubtitleAppearanceStyle.positionMin, maxValue: SubtitleAppearanceStyle.positionMax, target: nil, action: nil)
    let positionValueLabel = NSTextField(labelWithString: "Bottom")
    let scaleSlider = NSSlider(value: 1, minValue: SubtitleAppearanceStyle.scaleMin, maxValue: SubtitleAppearanceStyle.scaleMax, target: nil, action: nil)
    let scaleValueLabel = NSTextField(labelWithString: "1.0×")

    let fontSizeSlider = NSSlider(value: 36, minValue: SubtitleAppearanceStyle.fontSizeMin, maxValue: SubtitleAppearanceStyle.fontSizeMax, target: nil, action: nil)
    let fontSizeValueLabel = NSTextField(labelWithString: "36 pt")
    let fontFamilyLabel = NSTextField(labelWithString: SubtitleFont.assFontName)
    let fontColorWell = SettingsColorWell()
    let borderWidthSlider = NSSlider(value: 2, minValue: SubtitleAppearanceStyle.borderWidthMin, maxValue: SubtitleAppearanceStyle.borderWidthMax, target: nil, action: nil)
    let borderWidthValueLabel = NSTextField(labelWithString: "2")
    let borderColorWell = SettingsColorWell()
    let backgroundEnabledCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let backgroundColorWell = SettingsColorWell()
    let resetAppearanceButton = NSButton(title: "Reset to defaults", target: nil, action: nil)

    init() {
        [primaryTrackPopUp, secondaryTrackPopUp].forEach {
            $0.controlSize = .small
            $0.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        extendedOnlyLabel.font = .systemFont(ofSize: 11)
        extendedOnlyLabel.textColor = .secondaryLabelColor
        extendedOnlyLabel.maximumNumberOfLines = 0
        extendedOnlyLabel.stringValue =
            "Secondary subtitles, delay, styling, and sidecar load need extended playback (DirectMpv). Re-open via the button below when sidecars or embedded subs need mpv."

        externalFileLabel.font = .systemFont(ofSize: 11)
        externalFileLabel.textColor = .secondaryLabelColor
        externalFileLabel.lineBreakMode = .byTruncatingMiddle

        companionFilesLabel.font = .systemFont(ofSize: 11)
        companionFilesLabel.textColor = .secondaryLabelColor
        companionFilesLabel.maximumNumberOfLines = 0
        companionFilesLabel.isHidden = true

        extendedPlaybackButton.bezelStyle = .rounded
        extendedPlaybackButton.controlSize = .small
        extendedPlaybackButton.isHidden = true

        loadExternalButton.bezelStyle = .rounded
        loadExternalButton.controlSize = .small

        resetAppearanceButton.bezelStyle = .rounded
        resetAppearanceButton.controlSize = .small
        resetAppearanceButton.font = .systemFont(ofSize: 12)

        [delayValueLabel, positionValueLabel, scaleValueLabel, fontSizeValueLabel, borderWidthValueLabel].forEach {
            $0.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            $0.textColor = .secondaryLabelColor
            $0.alignment = .right
            $0.setContentHuggingPriority(.required, for: .horizontal)
        }

        fontFamilyLabel.font = .systemFont(ofSize: 13)
        fontFamilyLabel.textColor = .labelColor
        fontFamilyLabel.alignment = .right
        fontFamilyLabel.setContentHuggingPriority(.required, for: .horizontal)

        [delaySlider, positionSlider, scaleSlider, fontSizeSlider, borderWidthSlider].forEach {
            $0.controlSize = .small
            $0.isContinuous = true
        }

        [fontColorWell, borderColorWell, backgroundColorWell].forEach {
            $0.setContentHuggingPriority(.required, for: .horizontal)
        }

        let trackH = SubtitleAppearanceStyle.settingsSliderTrackHeight
        delaySlider.useFlatBarAppearance(trackHeight: trackH, filledColor: LaughTheme.accent)
        positionSlider.useFlatBarAppearance(trackHeight: trackH, filledColor: LaughTheme.accent)
        scaleSlider.useFlatBarAppearance(trackHeight: trackH, filledColor: LaughTheme.accent)
        fontSizeSlider.useFlatBarAppearance(trackHeight: trackH, filledColor: LaughTheme.accent)
        borderWidthSlider.useFlatBarAppearance(trackHeight: trackH, filledColor: LaughTheme.accent)

        LaughTheme.applySettingsAccentChrome(to: primaryTrackPopUp)
        LaughTheme.applySettingsAccentChrome(to: secondaryTrackPopUp)
        LaughTheme.applySettingsAccentChrome(to: backgroundEnabledCheckbox)
        LaughTheme.applySettingsAccentChrome(to: loadExternalButton)
        LaughTheme.applySettingsAccentChrome(to: extendedPlaybackButton)
        LaughTheme.applySettingsAccentChrome(to: resetAppearanceButton)
    }

    func applyDefaultsToControls() {
        delaySlider.doubleValue = SubtitleAppearanceStyle.defaultDelaySec
        positionSlider.doubleValue = SubtitleAppearanceStyle.defaultPosition
        scaleSlider.doubleValue = SubtitleAppearanceStyle.defaultScale
        fontSizeSlider.doubleValue = SubtitleAppearanceStyle.defaultFontSize
        borderWidthSlider.doubleValue = SubtitleAppearanceStyle.defaultBorderWidth
        setColorWellColors(
            font: SubtitleAppearanceStyle.defaultFontColor,
            border: SubtitleAppearanceStyle.defaultBorderColor,
            background: SubtitleAppearanceStyle.defaultBackgroundColor
        )
        backgroundEnabledCheckbox.state = SubtitleAppearanceStyle.defaultBackgroundEnabled ? .on : .off
        updateValueLabels()
    }

    private func setColorWellColors(font: NSColor, border: NSColor, background: NSColor) {
        for well in [fontColorWell, borderColorWell, backgroundColorWell] {
            well.suppressNotifications = true
        }
        fontColorWell.color = font
        borderColorWell.color = border
        backgroundColorWell.color = background
        for well in [fontColorWell, borderColorWell, backgroundColorWell] {
            well.suppressNotifications = false
        }
    }

    func loadAppearanceFromStore() {
        let store = SettingsStore.shared
        delaySlider.doubleValue = store.subtitleDelaySec
        positionSlider.doubleValue = store.subtitlePosition
        scaleSlider.doubleValue = store.subtitleScale
        fontSizeSlider.doubleValue = store.subtitleFontSize
        borderWidthSlider.doubleValue = store.subtitleBorderWidth
        setColorWellColors(
            font: store.subtitleFontColor,
            border: store.subtitleBorderColor,
            background: store.subtitleBackgroundColor
        )
        backgroundEnabledCheckbox.state = store.subtitleBackgroundEnabled ? .on : .off
        updateValueLabels()
    }

    func saveAppearanceToStore() {
        let store = SettingsStore.shared
        store.subtitleDelaySec = delaySlider.doubleValue
        store.subtitlePosition = positionSlider.doubleValue
        store.subtitleScale = scaleSlider.doubleValue
        store.subtitleFontSize = fontSizeSlider.doubleValue
        store.subtitleBorderWidth = borderWidthSlider.doubleValue
        store.subtitleFontColor = fontColorWell.color
        store.subtitleBorderColor = borderColorWell.color
        store.subtitleBackgroundEnabled = backgroundEnabledCheckbox.state == .on
        store.subtitleBackgroundColor = backgroundColorWell.color
    }

    func updateValueLabels() {
        delayValueLabel.stringValue = String(format: "%+.1f s", delaySlider.doubleValue)
        positionValueLabel.stringValue = SubtitleAppearanceStyle.positionLabel(
            for: positionSlider.doubleValue
        )
        scaleValueLabel.stringValue = String(format: "%.2f×", scaleSlider.doubleValue)
        fontSizeValueLabel.stringValue = "\(Int(round(fontSizeSlider.doubleValue))) pt"
        borderWidthValueLabel.stringValue = "\(Int(round(borderWidthSlider.doubleValue)))"
    }

    func setAppearanceControlsEnabled(_ enabled: Bool, delayEnabled: Bool = true) {
        [
            positionSlider, scaleSlider,
            fontSizeSlider, borderWidthSlider,
            fontColorWell, borderColorWell, backgroundColorWell,
            backgroundEnabledCheckbox
        ].forEach { $0.isEnabled = enabled }
        delaySlider.isEnabled = enabled && delayEnabled
    }

    func setMpvExclusiveControlsEnabled(_ extended: Bool) {
        secondaryEnabledSwitch.isEnabled = extended
        secondaryTrackPopUp.isEnabled = extended
        loadExternalButton.isEnabled = extended
    }

    func updateExtendedHint(extendedActive: Bool, nativePlayback: Bool) {
        if extendedActive {
            extendedOnlyLabel.isHidden = true
            return
        }
        extendedOnlyLabel.isHidden = false
        if nativePlayback {
            extendedOnlyLabel.stringValue =
                "Font, color, position, and scale apply while you adjust the sliders. Subtitle delay and bitmap (PGS) subs need extended playback — use the button above."
        } else {
            extendedOnlyLabel.stringValue =
                "Subtitle timing and styling need extended playback. Use the button above to switch."
        }
    }

    /// Legacy name — enables appearance sliders only.
    func setExtendedControlsEnabled(_ enabled: Bool) {
        setAppearanceControlsEnabled(enabled)
        setMpvExclusiveControlsEnabled(enabled)
        extendedOnlyLabel.isHidden = enabled
    }
}
