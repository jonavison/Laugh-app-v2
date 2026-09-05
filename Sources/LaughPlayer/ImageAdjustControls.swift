import AppKit

/// AppKit slider adapter for `ImageAdjustSession`. Owns widgets only — not parameter state.
final class ImageAdjustControls: NSObject {
    // Develop
    let exposureSlider = NSSlider(value: 0, minValue: -2, maxValue: 2, target: nil, action: nil)
    let brightnessSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let contrastSlider = NSSlider(value: 1, minValue: 0.25, maxValue: 2, target: nil, action: nil)
    let highlightsSlider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    let shadowsSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let whitesSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let blacksSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let exposureValueLabel = NSTextField(labelWithString: "0.00")
    let brightnessValueLabel = NSTextField(labelWithString: "0.00")
    let contrastValueLabel = NSTextField(labelWithString: "1.00")
    let highlightsValueLabel = NSTextField(labelWithString: "1.00")
    let shadowsValueLabel = NSTextField(labelWithString: "0.00")
    let whitesValueLabel = NSTextField(labelWithString: "0.00")
    let blacksValueLabel = NSTextField(labelWithString: "0.00")

    // Color
    let saturationSlider = NSSlider(value: 1, minValue: 0, maxValue: 2, target: nil, action: nil)
    let vibranceSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let hueSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let temperatureSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let tintSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let colorBalanceSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let splitHighlightSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let splitShadowSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let splitAmountSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let dramaticSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let moodSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let matteSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let glowSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let glowRadiusSlider = NSSlider(value: 0.45, minValue: 0, maxValue: 1, target: nil, action: nil)
    let blurSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let filmGrainSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let filmGrainSizeSlider = NSSlider(value: 0.45, minValue: 0, maxValue: 1, target: nil, action: nil)
    let mysticalSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let mysticalHazeSlider = NSSlider(value: 0.4, minValue: 0, maxValue: 1, target: nil, action: nil)
    let mysticalHueSlider = NSSlider(value: -0.25, minValue: -1, maxValue: 1, target: nil, action: nil)
    let toningAmountSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let toningHighlightsSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let toningShadowsSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let highKeySlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let highKeySoftnessSlider = NSSlider(value: 0.35, minValue: 0, maxValue: 1, target: nil, action: nil)
    let supercontrastSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let supercontrastMidtonesSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    let colorHarmonySlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let colorHarmonyBalanceSlider = NSSlider(value: 0.15, minValue: -1, maxValue: 1, target: nil, action: nil)
    let sunraysSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let sunraysLengthSlider = NSSlider(value: 0.55, minValue: 0, maxValue: 1, target: nil, action: nil)
    let sunraysWarmthSlider = NSSlider(value: 0.45, minValue: 0, maxValue: 1, target: nil, action: nil)
    let landscapeSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let landscapeFoliageSlider = NSSlider(value: 0.55, minValue: 0, maxValue: 1, target: nil, action: nil)
    let landscapeSkySlider = NSSlider(value: 0.45, minValue: 0, maxValue: 1, target: nil, action: nil)
    let blackAndWhiteSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let bwContrastSlider = NSSlider(value: 0.15, minValue: -1, maxValue: 1, target: nil, action: nil)
    let bwWarmthSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let saturationValueLabel = NSTextField(labelWithString: "1.00")
    let vibranceValueLabel = NSTextField(labelWithString: "0.00")
    let hueValueLabel = NSTextField(labelWithString: "0.00")
    let temperatureValueLabel = NSTextField(labelWithString: "0.00")
    let tintValueLabel = NSTextField(labelWithString: "0.00")
    let colorBalanceValueLabel = NSTextField(labelWithString: "0.00")
    let splitHighlightValueLabel = NSTextField(labelWithString: "0.00")
    let splitShadowValueLabel = NSTextField(labelWithString: "0.00")
    let splitAmountValueLabel = NSTextField(labelWithString: "0.00")
    let dramaticValueLabel = NSTextField(labelWithString: "0.00")
    let moodValueLabel = NSTextField(labelWithString: "0.00")
    let matteValueLabel = NSTextField(labelWithString: "0.00")
    let glowValueLabel = NSTextField(labelWithString: "0.00")
    let glowRadiusValueLabel = NSTextField(labelWithString: "0.45")
    let blurValueLabel = NSTextField(labelWithString: "0.00")
    let filmGrainValueLabel = NSTextField(labelWithString: "0.00")
    let filmGrainSizeValueLabel = NSTextField(labelWithString: "0.45")
    let mysticalValueLabel = NSTextField(labelWithString: "0.00")
    let mysticalHazeValueLabel = NSTextField(labelWithString: "0.40")
    let mysticalHueValueLabel = NSTextField(labelWithString: "-0.25")
    let toningAmountValueLabel = NSTextField(labelWithString: "0.00")
    let toningHighlightsValueLabel = NSTextField(labelWithString: "0.00")
    let toningShadowsValueLabel = NSTextField(labelWithString: "0.00")
    let highKeyValueLabel = NSTextField(labelWithString: "0.00")
    let highKeySoftnessValueLabel = NSTextField(labelWithString: "0.35")
    let supercontrastValueLabel = NSTextField(labelWithString: "0.00")
    let supercontrastMidtonesValueLabel = NSTextField(labelWithString: "0.50")
    let colorHarmonyValueLabel = NSTextField(labelWithString: "0.00")
    let colorHarmonyBalanceValueLabel = NSTextField(labelWithString: "+0.15")
    let sunraysValueLabel = NSTextField(labelWithString: "0.00")
    let sunraysLengthValueLabel = NSTextField(labelWithString: "0.55")
    let sunraysWarmthValueLabel = NSTextField(labelWithString: "0.45")
    let landscapeValueLabel = NSTextField(labelWithString: "0.00")
    let landscapeFoliageValueLabel = NSTextField(labelWithString: "0.55")
    let landscapeSkyValueLabel = NSTextField(labelWithString: "0.45")
    let blackAndWhiteValueLabel = NSTextField(labelWithString: "0.00")
    let bwContrastValueLabel = NSTextField(labelWithString: "+0.15")
    let bwWarmthValueLabel = NSTextField(labelWithString: "0.00")

    // Details / Denoise
    let sharpnessSlider = NSSlider(value: 0, minValue: 0, maxValue: 2, target: nil, action: nil)
    let definitionSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let structureSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let denoiseSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let sharpnessValueLabel = NSTextField(labelWithString: "0.00")
    let definitionValueLabel = NSTextField(labelWithString: "0.00")
    let structureValueLabel = NSTextField(labelWithString: "0.00")
    let denoiseValueLabel = NSTextField(labelWithString: "0.00")

    // Vignette / Dodge & Burn
    let vignetteSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let vignetteMidpointSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    let vignetteValueLabel = NSTextField(labelWithString: "0.00")
    let vignetteMidpointValueLabel = NSTextField(labelWithString: "0.50")
    let dodgeBurnSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let dodgeBurnRangeSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let dodgeBurnSoftnessSlider = NSSlider(value: 0.45, minValue: 0, maxValue: 1, target: nil, action: nil)
    let dodgeBurnValueLabel = NSTextField(labelWithString: "0.00")
    let dodgeBurnRangeValueLabel = NSTextField(labelWithString: "0.00")
    let dodgeBurnSoftnessValueLabel = NSTextField(labelWithString: "0.45")

    private weak var session: ImageAdjustSession?
    private var isPullingFromSession = false

    private var allSliders: [NSSlider] {
        [
            exposureSlider, brightnessSlider, contrastSlider, highlightsSlider, shadowsSlider,
            whitesSlider, blacksSlider,
            saturationSlider, vibranceSlider, hueSlider, temperatureSlider, tintSlider,
            colorBalanceSlider, splitHighlightSlider, splitShadowSlider, splitAmountSlider,
            dramaticSlider, moodSlider, matteSlider,
            glowSlider, glowRadiusSlider, blurSlider, filmGrainSlider, filmGrainSizeSlider,
            mysticalSlider, mysticalHazeSlider, mysticalHueSlider,
            toningAmountSlider, toningHighlightsSlider, toningShadowsSlider,
            highKeySlider, highKeySoftnessSlider, supercontrastSlider, supercontrastMidtonesSlider,
            colorHarmonySlider, colorHarmonyBalanceSlider,
            sunraysSlider, sunraysLengthSlider, sunraysWarmthSlider,
            landscapeSlider, landscapeFoliageSlider, landscapeSkySlider,
            blackAndWhiteSlider, bwContrastSlider, bwWarmthSlider,
            sharpnessSlider, definitionSlider, structureSlider, denoiseSlider,
            vignetteSlider, vignetteMidpointSlider,
            dodgeBurnSlider, dodgeBurnRangeSlider, dodgeBurnSoftnessSlider
        ]
    }

    private var allValueLabels: [NSTextField] {
        [
            exposureValueLabel, brightnessValueLabel, contrastValueLabel, highlightsValueLabel, shadowsValueLabel,
            whitesValueLabel, blacksValueLabel,
            saturationValueLabel, vibranceValueLabel, hueValueLabel, temperatureValueLabel, tintValueLabel,
            colorBalanceValueLabel, splitHighlightValueLabel, splitShadowValueLabel,             splitAmountValueLabel,
            dramaticValueLabel,
            moodValueLabel,
            matteValueLabel,
            glowValueLabel,
            glowRadiusValueLabel,
            blurValueLabel,
            filmGrainValueLabel,
            filmGrainSizeValueLabel,
            mysticalValueLabel,
            mysticalHazeValueLabel,
            mysticalHueValueLabel,
            toningAmountValueLabel,
            toningHighlightsValueLabel,
            toningShadowsValueLabel,
            highKeyValueLabel,
            highKeySoftnessValueLabel,
            supercontrastValueLabel,
            supercontrastMidtonesValueLabel,
            colorHarmonyValueLabel,
            colorHarmonyBalanceValueLabel,
            sunraysValueLabel,
            sunraysLengthValueLabel,
            sunraysWarmthValueLabel,
            landscapeValueLabel,
            landscapeFoliageValueLabel,
            landscapeSkyValueLabel,
            blackAndWhiteValueLabel,
            bwContrastValueLabel,
            bwWarmthValueLabel,
            sharpnessValueLabel, definitionValueLabel, structureValueLabel, denoiseValueLabel,
            vignetteValueLabel,
            vignetteMidpointValueLabel,
            dodgeBurnValueLabel,
            dodgeBurnRangeValueLabel,
            dodgeBurnSoftnessValueLabel
        ]
    }

    private var parametersFromSliders: ImageAdjustParameters {
        ImageAdjustParameters(
            exposure: exposureSlider.doubleValue,
            brightness: brightnessSlider.doubleValue,
            contrast: contrastSlider.doubleValue,
            highlights: highlightsSlider.doubleValue,
            shadows: shadowsSlider.doubleValue,
            whites: whitesSlider.doubleValue,
            blacks: blacksSlider.doubleValue,
            saturation: saturationSlider.doubleValue,
            vibrance: vibranceSlider.doubleValue,
            hue: hueSlider.doubleValue,
            temperature: temperatureSlider.doubleValue,
            tint: tintSlider.doubleValue,
            colorBalance: colorBalanceSlider.doubleValue,
            splitHighlight: splitHighlightSlider.doubleValue,
            splitShadow: splitShadowSlider.doubleValue,
            splitAmount: splitAmountSlider.doubleValue,
            dramatic: dramaticSlider.doubleValue,
            mood: moodSlider.doubleValue,
            matte: matteSlider.doubleValue,
            glow: glowSlider.doubleValue,
            glowRadius: glowRadiusSlider.doubleValue,
            blur: blurSlider.doubleValue,
            filmGrain: filmGrainSlider.doubleValue,
            filmGrainSize: filmGrainSizeSlider.doubleValue,
            mystical: mysticalSlider.doubleValue,
            mysticalHaze: mysticalHazeSlider.doubleValue,
            mysticalHue: mysticalHueSlider.doubleValue,
            toningAmount: toningAmountSlider.doubleValue,
            toningHighlights: toningHighlightsSlider.doubleValue,
            toningShadows: toningShadowsSlider.doubleValue,
            highKey: highKeySlider.doubleValue,
            highKeySoftness: highKeySoftnessSlider.doubleValue,
            supercontrast: supercontrastSlider.doubleValue,
            supercontrastMidtones: supercontrastMidtonesSlider.doubleValue,
            colorHarmony: colorHarmonySlider.doubleValue,
            colorHarmonyBalance: colorHarmonyBalanceSlider.doubleValue,
            sunrays: sunraysSlider.doubleValue,
            sunraysLength: sunraysLengthSlider.doubleValue,
            sunraysWarmth: sunraysWarmthSlider.doubleValue,
            landscape: landscapeSlider.doubleValue,
            landscapeFoliage: landscapeFoliageSlider.doubleValue,
            landscapeSky: landscapeSkySlider.doubleValue,
            blackAndWhite: blackAndWhiteSlider.doubleValue,
            bwContrast: bwContrastSlider.doubleValue,
            bwWarmth: bwWarmthSlider.doubleValue,
            sharpness: sharpnessSlider.doubleValue,
            definition: definitionSlider.doubleValue,
            structure: structureSlider.doubleValue,
            denoise: denoiseSlider.doubleValue,
            vignette: vignetteSlider.doubleValue,
            vignetteMidpoint: vignetteMidpointSlider.doubleValue,
            dodgeBurn: dodgeBurnSlider.doubleValue,
            dodgeBurnRange: dodgeBurnRangeSlider.doubleValue,
            dodgeBurnSoftness: dodgeBurnSoftnessSlider.doubleValue
        )
    }

    func bind(to session: ImageAdjustSession) {
        self.session = session
        session.onParametersCommitted = { [weak self] in
            self?.pullFromSession()
        }
        for slider in allSliders {
            slider.isContinuous = true
            slider.controlSize = .small
            slider.target = self
            slider.action = #selector(sliderChanged)
        }
        for label in allValueLabels {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.setContentHuggingPriority(.required, for: .horizontal)
        }
        pullFromSession()
    }

    /// Sync widgets from the session after presets / reset / external apply.
    func pullFromSession() {
        guard let session else { return }
        isPullingFromSession = true
        defer { isPullingFromSession = false }
        writeSliders(from: session.rawParameters)
        refreshValueLabels()
    }

    @objc private func sliderChanged() {
        guard !isPullingFromSession else { return }
        refreshValueLabels()
        session?.replaceParameters(parametersFromSliders)
    }

    private func writeSliders(from parameters: ImageAdjustParameters) {
        exposureSlider.doubleValue = parameters.exposure
        brightnessSlider.doubleValue = parameters.brightness
        contrastSlider.doubleValue = parameters.contrast
        highlightsSlider.doubleValue = parameters.highlights
        shadowsSlider.doubleValue = parameters.shadows
        whitesSlider.doubleValue = parameters.whites
        blacksSlider.doubleValue = parameters.blacks
        saturationSlider.doubleValue = parameters.saturation
        vibranceSlider.doubleValue = parameters.vibrance
        hueSlider.doubleValue = parameters.hue
        temperatureSlider.doubleValue = parameters.temperature
        tintSlider.doubleValue = parameters.tint
        colorBalanceSlider.doubleValue = parameters.colorBalance
        splitHighlightSlider.doubleValue = parameters.splitHighlight
        splitShadowSlider.doubleValue = parameters.splitShadow
        splitAmountSlider.doubleValue = parameters.splitAmount
        dramaticSlider.doubleValue = parameters.dramatic
        moodSlider.doubleValue = parameters.mood
        matteSlider.doubleValue = parameters.matte
        glowSlider.doubleValue = parameters.glow
        glowRadiusSlider.doubleValue = parameters.glowRadius
        blurSlider.doubleValue = parameters.blur
        filmGrainSlider.doubleValue = parameters.filmGrain
        filmGrainSizeSlider.doubleValue = parameters.filmGrainSize
        mysticalSlider.doubleValue = parameters.mystical
        mysticalHazeSlider.doubleValue = parameters.mysticalHaze
        mysticalHueSlider.doubleValue = parameters.mysticalHue
        toningAmountSlider.doubleValue = parameters.toningAmount
        toningHighlightsSlider.doubleValue = parameters.toningHighlights
        toningShadowsSlider.doubleValue = parameters.toningShadows
        highKeySlider.doubleValue = parameters.highKey
        highKeySoftnessSlider.doubleValue = parameters.highKeySoftness
        supercontrastSlider.doubleValue = parameters.supercontrast
        supercontrastMidtonesSlider.doubleValue = parameters.supercontrastMidtones
        colorHarmonySlider.doubleValue = parameters.colorHarmony
        colorHarmonyBalanceSlider.doubleValue = parameters.colorHarmonyBalance
        sunraysSlider.doubleValue = parameters.sunrays
        sunraysLengthSlider.doubleValue = parameters.sunraysLength
        sunraysWarmthSlider.doubleValue = parameters.sunraysWarmth
        landscapeSlider.doubleValue = parameters.landscape
        landscapeFoliageSlider.doubleValue = parameters.landscapeFoliage
        landscapeSkySlider.doubleValue = parameters.landscapeSky
        blackAndWhiteSlider.doubleValue = parameters.blackAndWhite
        bwContrastSlider.doubleValue = parameters.bwContrast
        bwWarmthSlider.doubleValue = parameters.bwWarmth
        sharpnessSlider.doubleValue = parameters.sharpness
        definitionSlider.doubleValue = parameters.definition
        structureSlider.doubleValue = parameters.structure
        denoiseSlider.doubleValue = parameters.denoise
        vignetteSlider.doubleValue = parameters.vignette
        vignetteMidpointSlider.doubleValue = parameters.vignetteMidpoint
        dodgeBurnSlider.doubleValue = parameters.dodgeBurn
        dodgeBurnRangeSlider.doubleValue = parameters.dodgeBurnRange
        dodgeBurnSoftnessSlider.doubleValue = parameters.dodgeBurnSoftness
    }

    private func refreshValueLabels() {
        exposureValueLabel.stringValue = String(format: "%+.2f", exposureSlider.doubleValue)
        brightnessValueLabel.stringValue = String(format: "%+.2f", brightnessSlider.doubleValue)
        contrastValueLabel.stringValue = String(format: "%.2f", contrastSlider.doubleValue)
        highlightsValueLabel.stringValue = String(format: "%.2f", highlightsSlider.doubleValue)
        shadowsValueLabel.stringValue = String(format: "%+.2f", shadowsSlider.doubleValue)
        whitesValueLabel.stringValue = String(format: "%+.2f", whitesSlider.doubleValue)
        blacksValueLabel.stringValue = String(format: "%+.2f", blacksSlider.doubleValue)
        saturationValueLabel.stringValue = String(format: "%.2f", saturationSlider.doubleValue)
        vibranceValueLabel.stringValue = String(format: "%+.2f", vibranceSlider.doubleValue)
        hueValueLabel.stringValue = String(format: "%+.2f", hueSlider.doubleValue)
        temperatureValueLabel.stringValue = String(format: "%+.2f", temperatureSlider.doubleValue)
        tintValueLabel.stringValue = String(format: "%+.2f", tintSlider.doubleValue)
        colorBalanceValueLabel.stringValue = String(format: "%+.2f", colorBalanceSlider.doubleValue)
        splitHighlightValueLabel.stringValue = String(format: "%+.2f", splitHighlightSlider.doubleValue)
        splitShadowValueLabel.stringValue = String(format: "%+.2f", splitShadowSlider.doubleValue)
        splitAmountValueLabel.stringValue = String(format: "%.2f", splitAmountSlider.doubleValue)
        dramaticValueLabel.stringValue = String(format: "%.2f", dramaticSlider.doubleValue)
        moodValueLabel.stringValue = String(format: "%.2f", moodSlider.doubleValue)
        matteValueLabel.stringValue = String(format: "%.2f", matteSlider.doubleValue)
        glowValueLabel.stringValue = String(format: "%.2f", glowSlider.doubleValue)
        glowRadiusValueLabel.stringValue = String(format: "%.2f", glowRadiusSlider.doubleValue)
        blurValueLabel.stringValue = String(format: "%.2f", blurSlider.doubleValue)
        filmGrainValueLabel.stringValue = String(format: "%.2f", filmGrainSlider.doubleValue)
        filmGrainSizeValueLabel.stringValue = String(format: "%.2f", filmGrainSizeSlider.doubleValue)
        mysticalValueLabel.stringValue = String(format: "%.2f", mysticalSlider.doubleValue)
        mysticalHazeValueLabel.stringValue = String(format: "%.2f", mysticalHazeSlider.doubleValue)
        mysticalHueValueLabel.stringValue = String(format: "%+.2f", mysticalHueSlider.doubleValue)
        toningAmountValueLabel.stringValue = String(format: "%.2f", toningAmountSlider.doubleValue)
        toningHighlightsValueLabel.stringValue = String(format: "%+.2f", toningHighlightsSlider.doubleValue)
        toningShadowsValueLabel.stringValue = String(format: "%+.2f", toningShadowsSlider.doubleValue)
        highKeyValueLabel.stringValue = String(format: "%.2f", highKeySlider.doubleValue)
        highKeySoftnessValueLabel.stringValue = String(format: "%.2f", highKeySoftnessSlider.doubleValue)
        supercontrastValueLabel.stringValue = String(format: "%.2f", supercontrastSlider.doubleValue)
        supercontrastMidtonesValueLabel.stringValue = String(format: "%.2f", supercontrastMidtonesSlider.doubleValue)
        colorHarmonyValueLabel.stringValue = String(format: "%.2f", colorHarmonySlider.doubleValue)
        colorHarmonyBalanceValueLabel.stringValue = String(format: "%+.2f", colorHarmonyBalanceSlider.doubleValue)
        sunraysValueLabel.stringValue = String(format: "%.2f", sunraysSlider.doubleValue)
        sunraysLengthValueLabel.stringValue = String(format: "%.2f", sunraysLengthSlider.doubleValue)
        sunraysWarmthValueLabel.stringValue = String(format: "%.2f", sunraysWarmthSlider.doubleValue)
        landscapeValueLabel.stringValue = String(format: "%.2f", landscapeSlider.doubleValue)
        landscapeFoliageValueLabel.stringValue = String(format: "%.2f", landscapeFoliageSlider.doubleValue)
        landscapeSkyValueLabel.stringValue = String(format: "%.2f", landscapeSkySlider.doubleValue)
        blackAndWhiteValueLabel.stringValue = String(format: "%.2f", blackAndWhiteSlider.doubleValue)
        bwContrastValueLabel.stringValue = String(format: "%+.2f", bwContrastSlider.doubleValue)
        bwWarmthValueLabel.stringValue = String(format: "%+.2f", bwWarmthSlider.doubleValue)
        sharpnessValueLabel.stringValue = String(format: "%.2f", sharpnessSlider.doubleValue)
        definitionValueLabel.stringValue = String(format: "%+.2f", definitionSlider.doubleValue)
        structureValueLabel.stringValue = String(format: "%+.2f", structureSlider.doubleValue)
        denoiseValueLabel.stringValue = String(format: "%.2f", denoiseSlider.doubleValue)
        vignetteValueLabel.stringValue = String(format: "%.2f", vignetteSlider.doubleValue)
        vignetteMidpointValueLabel.stringValue = String(format: "%.2f", vignetteMidpointSlider.doubleValue)
        dodgeBurnValueLabel.stringValue = String(format: "%+.2f", dodgeBurnSlider.doubleValue)
        dodgeBurnRangeValueLabel.stringValue = String(format: "%+.2f", dodgeBurnRangeSlider.doubleValue)
        dodgeBurnSoftnessValueLabel.stringValue = String(format: "%.2f", dodgeBurnSoftnessSlider.doubleValue)
    }
}
