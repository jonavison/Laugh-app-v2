import AppKit

/// Audio tab widgets (track picker + 10-band EQ).
final class AudioSettingsControls {
    let trackPopUp = NSPopUpButton()
    let eqPresetPopUp = NSPopUpButton()
    let eqUnavailableLabel = NSTextField(labelWithString: "")
    let eqBandsRow = NSStackView()
    let eqBandSliders: [NSSlider]
    private let eqBandLabels: [NSTextField]

    init() {
        trackPopUp.controlSize = .small
        trackPopUp.setContentHuggingPriority(.defaultLow, for: .horizontal)

        eqPresetPopUp.controlSize = .small
        for preset in PlaybackEQPreset.allCases {
            eqPresetPopUp.addItem(withTitle: preset.displayTitle)
            eqPresetPopUp.lastItem?.representedObject = preset.rawValue
        }

        eqUnavailableLabel.textColor = .secondaryLabelColor
        eqUnavailableLabel.font = .systemFont(ofSize: 11)
        eqUnavailableLabel.maximumNumberOfLines = 0
        eqUnavailableLabel.stringValue =
            "Equalizer is available with extended playback (MKV/direct) only."

        eqBandsRow.orientation = .horizontal
        eqBandsRow.alignment = .bottom
        eqBandsRow.distribution = .fillEqually
        eqBandsRow.spacing = 4

        var sliders: [NSSlider] = []
        var labels: [NSTextField] = []
        for (index, bandLabel) in PlaybackEQ.bandLabels.enumerated() {
            let column = NSStackView()
            column.orientation = .vertical
            column.alignment = .centerX
            column.spacing = 2

            let slider = NSSlider(
                value: 0,
                minValue: Double(PlaybackEQ.minGain),
                maxValue: Double(PlaybackEQ.maxGain),
                target: nil,
                action: nil
            )
            slider.isVertical = true
            slider.controlSize = .mini
            slider.tag = index
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.heightAnchor.constraint(equalToConstant: 88).isActive = true
            let label = NSTextField(labelWithString: bandLabel)
            label.font = .systemFont(ofSize: 9)
            label.textColor = .tertiaryLabelColor

            column.addArrangedSubview(slider)
            column.addArrangedSubview(label)
            eqBandsRow.addArrangedSubview(column)
            sliders.append(slider)
            labels.append(label)
        }
        eqBandSliders = sliders
        eqBandLabels = labels
        LaughTheme.applySettingsAccentChrome(to: trackPopUp)
        LaughTheme.applySettingsAccentChrome(to: eqPresetPopUp)
        eqBandSliders.forEach { LaughTheme.applySettingsAccentChrome(to: $0) }
    }

    func setEQControlsEnabled(_ enabled: Bool) {
        eqPresetPopUp.isEnabled = enabled
        eqBandSliders.forEach { $0.isEnabled = enabled }
        eqUnavailableLabel.isHidden = enabled
    }

    func loadBandsFromStore() {
        let store = SettingsStore.shared
        let bands = store.playbackEQBands
        for (index, slider) in eqBandSliders.enumerated() where index < bands.count {
            slider.doubleValue = Double(bands[index])
        }
        if let item = eqPresetPopUp.itemArray.first(where: {
            ($0.representedObject as? String) == store.playbackEQPreset.rawValue
        }) {
            eqPresetPopUp.select(item)
        }
    }

    func bandsFromSliders() -> [Float] {
        eqBandSliders.map { Float($0.doubleValue) }
    }
}
