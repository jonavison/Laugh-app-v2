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
    let positionSlider = NSSlider(value: 100, minValue: SubtitleAppearanceStyle.positionMin, maxValue: SubtitleAppearanceStyle.positionMax, target: nil, action: nil)
    let positionValueLabel = NSTextField(labelWithString: "Bottom")
    let scaleSlider = NSSlider(value: 1, minValue: SubtitleAppearanceStyle.scaleMin, maxValue: SubtitleAppearanceStyle.scaleMax, target: nil, action: nil)
    let scaleValueLabel = NSTextField(labelWithString: "1.0×")

    let fontSizeSlider = NSSlider(value: 36, minValue: SubtitleAppearanceStyle.fontSizeMin, maxValue: SubtitleAppearanceStyle.fontSizeMax, target: nil, action: nil)
    let fontSizeValueLabel = NSTextField(labelWithString: "36 pt")
    let fontColorWell = NSColorWell()
    let borderWidthSlider = NSSlider(value: 2, minValue: SubtitleAppearanceStyle.borderWidthMin, maxValue: SubtitleAppearanceStyle.borderWidthMax, target: nil, action: nil)
    let borderWidthValueLabel = NSTextField(labelWithString: "2")
    let borderColorWell = NSColorWell()
    let backgroundEnabledCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let backgroundColorWell = NSColorWell()

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

        [delayValueLabel, positionValueLabel, scaleValueLabel, fontSizeValueLabel, borderWidthValueLabel].forEach {
            $0.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            $0.textColor = .secondaryLabelColor
            $0.alignment = .right
            $0.setContentHuggingPriority(.required, for: .horizontal)
        }

        [delaySlider, positionSlider, scaleSlider, fontSizeSlider, borderWidthSlider].forEach {
            $0.controlSize = .small
            $0.isContinuous = true
        }

        [fontColorWell, borderColorWell, backgroundColorWell].forEach {
            $0.isBordered = true
            $0.controlSize = .small
        }

        delaySlider.useFlatBarAppearance(trackHeight: 3, filledColor: LaughTheme.accent)
        positionSlider.useFlatBarAppearance(trackHeight: 3, filledColor: LaughTheme.accent)
        scaleSlider.useFlatBarAppearance(trackHeight: 3, filledColor: LaughTheme.accent)
        fontSizeSlider.useFlatBarAppearance(trackHeight: 3, filledColor: LaughTheme.accent)
        borderWidthSlider.useFlatBarAppearance(trackHeight: 3, filledColor: LaughTheme.accent)

        LaughTheme.applySettingsAccentChrome(to: primaryTrackPopUp)
        LaughTheme.applySettingsAccentChrome(to: secondaryTrackPopUp)
        LaughTheme.applySettingsAccentChrome(to: backgroundEnabledCheckbox)
        LaughTheme.applySettingsAccentChrome(to: loadExternalButton)
        LaughTheme.applySettingsAccentChrome(to: extendedPlaybackButton)
    }

    func loadAppearanceFromStore() {
        let store = SettingsStore.shared
        delaySlider.doubleValue = store.subtitleDelaySec
        positionSlider.doubleValue = store.subtitlePosition
        scaleSlider.doubleValue = store.subtitleScale
        fontSizeSlider.doubleValue = store.subtitleFontSize
        borderWidthSlider.doubleValue = store.subtitleBorderWidth
        fontColorWell.color = store.subtitleFontColor
        borderColorWell.color = store.subtitleBorderColor
        backgroundEnabledCheckbox.state = store.subtitleBackgroundEnabled ? .on : .off
        backgroundColorWell.color = store.subtitleBackgroundColor
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
        if positionSlider.doubleValue <= 20 {
            positionValueLabel.stringValue = "Top"
        } else if positionSlider.doubleValue >= 80 {
            positionValueLabel.stringValue = "Bottom"
        } else {
            positionValueLabel.stringValue = "Middle"
        }
        scaleValueLabel.stringValue = String(format: "%.2f×", scaleSlider.doubleValue)
        fontSizeValueLabel.stringValue = "\(Int(round(fontSizeSlider.doubleValue))) pt"
        borderWidthValueLabel.stringValue = "\(Int(round(borderWidthSlider.doubleValue)))"
    }

    func setExtendedControlsEnabled(_ enabled: Bool) {
        [
            delaySlider, positionSlider, scaleSlider,
            fontSizeSlider, borderWidthSlider,
            fontColorWell, borderColorWell, backgroundColorWell,
            secondaryEnabledSwitch, secondaryTrackPopUp,
            loadExternalButton, backgroundEnabledCheckbox
        ].forEach { $0.isEnabled = enabled }
        extendedOnlyLabel.isHidden = enabled
    }
}
