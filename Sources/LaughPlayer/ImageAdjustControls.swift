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
    let smartContrastSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let exposureValueLabel = NSTextField(labelWithString: "0.00")
    let brightnessValueLabel = NSTextField(labelWithString: "0.00")
    let contrastValueLabel = NSTextField(labelWithString: "1.00")
    let smartContrastValueLabel = NSTextField(labelWithString: "0.00")
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
    let whiteBalanceEyedropperButton = NSButton(title: "", target: nil, action: nil)
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

    // Details / Noise Reduction
    let sharpnessSlider = NSSlider(value: 0, minValue: 0, maxValue: 2, target: nil, action: nil)
    let sharpenRadiusSlider = NSSlider(value: 0.4, minValue: 0, maxValue: 1, target: nil, action: nil)
    let sharpenDetailSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    let definitionSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let structureSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let denoiseSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let denoiseColorSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let denoiseDetailSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    let sharpnessValueLabel = NSTextField(labelWithString: "0.00")
    let sharpenRadiusValueLabel = NSTextField(labelWithString: "0.40")
    let sharpenDetailValueLabel = NSTextField(labelWithString: "0.50")
    let definitionValueLabel = NSTextField(labelWithString: "0.00")
    let structureValueLabel = NSTextField(labelWithString: "0.00")
    let denoiseValueLabel = NSTextField(labelWithString: "0.00")
    let denoiseColorValueLabel = NSTextField(labelWithString: "0.00")
    let denoiseDetailValueLabel = NSTextField(labelWithString: "0.50")

    // Curves / HSL
    let curveChannelPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    let curveEditor = ImageToneCurveEditorView()
    let hslChannelPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    let hslHueSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let hslSatSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let hslLumaSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let hslHueValueLabel = NSTextField(labelWithString: "0.00")
    let hslSatValueLabel = NSTextField(labelWithString: "0.00")
    let hslLumaValueLabel = NSTextField(labelWithString: "0.00")

    // Vignette / Dodge & Burn / Optics
    let vignetteSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let vignetteMidpointSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    let vignetteCenterXSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    let vignetteCenterYSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    let vignetteValueLabel = NSTextField(labelWithString: "0.00")
    let vignetteMidpointValueLabel = NSTextField(labelWithString: "0.50")
    let vignetteCenterXValueLabel = NSTextField(labelWithString: "0.50")
    let vignetteCenterYValueLabel = NSTextField(labelWithString: "0.50")
    let dodgeBurnSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let dodgeBurnRangeSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let dodgeBurnSoftnessSlider = NSSlider(value: 0.45, minValue: 0, maxValue: 1, target: nil, action: nil)
    let dodgeBurnValueLabel = NSTextField(labelWithString: "0.00")
    let dodgeBurnRangeValueLabel = NSTextField(labelWithString: "0.00")
    let dodgeBurnSoftnessValueLabel = NSTextField(labelWithString: "0.45")
    let distortionSlider = NSSlider(value: 0, minValue: -1, maxValue: 1, target: nil, action: nil)
    let chromaticAberrationSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let defringePurpleSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let defringeGreenSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let distortionValueLabel = NSTextField(labelWithString: "0.00")
    let chromaticAberrationValueLabel = NSTextField(labelWithString: "0.00")
    let defringePurpleValueLabel = NSTextField(labelWithString: "0.00")
    let defringeGreenValueLabel = NSTextField(labelWithString: "0.00")

    /// Fired when the Color WB eyedropper is toggled on.
    var onWhiteBalanceEyedropperToggle: ((Bool) -> Void)?
    private(set) var isWhiteBalanceEyedropperActive = false

    private var curveLuma = ImageAdjustParameters.identityCurve
    private var curveRed = ImageAdjustParameters.identityCurve
    private var curveGreen = ImageAdjustParameters.identityCurve
    private var curveBlue = ImageAdjustParameters.identityCurve
    private var hslHue = Array(repeating: 0.0, count: ImageAdjustParameters.hslChannelCount)
    private var hslSat = Array(repeating: 0.0, count: ImageAdjustParameters.hslChannelCount)
    private var hslLuma = Array(repeating: 0.0, count: ImageAdjustParameters.hslChannelCount)

    private weak var session: ImageAdjustSession?
    private var isPullingFromSession = false

    private var allSliders: [NSSlider] {
        [
            exposureSlider, brightnessSlider, contrastSlider, smartContrastSlider,
            highlightsSlider, shadowsSlider,
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
            sharpnessSlider, sharpenRadiusSlider, sharpenDetailSlider,
            definitionSlider, structureSlider,
            denoiseSlider, denoiseColorSlider, denoiseDetailSlider,
            hslHueSlider, hslSatSlider, hslLumaSlider,
            vignetteSlider, vignetteMidpointSlider, vignetteCenterXSlider, vignetteCenterYSlider,
            dodgeBurnSlider, dodgeBurnRangeSlider, dodgeBurnSoftnessSlider,
            distortionSlider, chromaticAberrationSlider, defringePurpleSlider, defringeGreenSlider
        ]
    }

    private var allValueLabels: [NSTextField] {
        [
            exposureValueLabel, brightnessValueLabel, contrastValueLabel, smartContrastValueLabel,
            highlightsValueLabel, shadowsValueLabel,
            whitesValueLabel, blacksValueLabel,
            saturationValueLabel, vibranceValueLabel, hueValueLabel, temperatureValueLabel, tintValueLabel,
            colorBalanceValueLabel, splitHighlightValueLabel, splitShadowValueLabel, splitAmountValueLabel,
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
            sharpnessValueLabel, sharpenRadiusValueLabel, sharpenDetailValueLabel,
            definitionValueLabel, structureValueLabel,
            denoiseValueLabel, denoiseColorValueLabel, denoiseDetailValueLabel,
            hslHueValueLabel, hslSatValueLabel, hslLumaValueLabel,
            vignetteValueLabel,
            vignetteMidpointValueLabel,
            vignetteCenterXValueLabel,
            vignetteCenterYValueLabel,
            dodgeBurnValueLabel,
            dodgeBurnRangeValueLabel,
            dodgeBurnSoftnessValueLabel,
            distortionValueLabel,
            chromaticAberrationValueLabel,
            defringePurpleValueLabel,
            defringeGreenValueLabel
        ]
    }

    private var parametersFromSliders: ImageAdjustParameters {
        ImageAdjustParameters(
            exposure: exposureSlider.doubleValue,
            brightness: brightnessSlider.doubleValue,
            contrast: contrastSlider.doubleValue,
            smartContrast: smartContrastSlider.doubleValue,
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
            curveLuma: curveLuma,
            curveRed: curveRed,
            curveGreen: curveGreen,
            curveBlue: curveBlue,
            hslHue: hslHue,
            hslSat: hslSat,
            hslLuma: hslLuma,
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
            sharpenRadius: sharpenRadiusSlider.doubleValue,
            sharpenDetail: sharpenDetailSlider.doubleValue,
            definition: definitionSlider.doubleValue,
            structure: structureSlider.doubleValue,
            denoise: denoiseSlider.doubleValue,
            denoiseColor: denoiseColorSlider.doubleValue,
            denoiseDetail: denoiseDetailSlider.doubleValue,
            vignette: vignetteSlider.doubleValue,
            vignetteMidpoint: vignetteMidpointSlider.doubleValue,
            vignetteCenterX: vignetteCenterXSlider.doubleValue,
            vignetteCenterY: vignetteCenterYSlider.doubleValue,
            dodgeBurn: dodgeBurnSlider.doubleValue,
            dodgeBurnRange: dodgeBurnRangeSlider.doubleValue,
            dodgeBurnSoftness: dodgeBurnSoftnessSlider.doubleValue,
            distortion: distortionSlider.doubleValue,
            chromaticAberration: chromaticAberrationSlider.doubleValue,
            defringePurple: defringePurpleSlider.doubleValue,
            defringeGreen: defringeGreenSlider.doubleValue
        )
    }

    func bind(to session: ImageAdjustSession) {
        self.session = session
        session.onParametersCommitted = { [weak self] in
            self?.pullFromSession()
        }
        // Capture construction defaults (= identity) before any session pull overwrites them.
        installParameterResetDefaults()
        configureCurveAndHSLChrome()
        configureWhiteBalanceEyedropper()
        installSemanticTrackChrome()
        for slider in allSliders {
            slider.isContinuous = true
            slider.controlSize = .small
            slider.target = self
            slider.action = #selector(sliderChanged(_:))
            slider.toolTip = "Double-click the knob to reset"
        }
        for label in allValueLabels {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .right
            label.setContentHuggingPriority(.required, for: .horizontal)
        }
        pullFromSession()
    }

    func setWhiteBalanceEyedropperActive(_ active: Bool) {
        isWhiteBalanceEyedropperActive = active
        refreshEyedropperChrome()
    }

    func applyWhiteBalanceSample(temperature: Double, tint: Double) {
        temperatureSlider.doubleValue = max(-1, min(1, temperature))
        tintSlider.doubleValue = max(-1, min(1, tint))
        isWhiteBalanceEyedropperActive = false
        refreshEyedropperChrome()
        refreshValueLabels()
        session?.apply(parametersFromSliders, quality: .full, clearBypasses: false)
        onWhiteBalanceEyedropperToggle?(false)
    }

    func setVignetteCenter(x: Double, y: Double) {
        vignetteCenterXSlider.doubleValue = max(0, min(1, x))
        vignetteCenterYSlider.doubleValue = max(0, min(1, y))
        refreshValueLabels()
        session?.replaceParameters(parametersFromSliders)
    }

    private func configureCurveAndHSLChrome() {
        curveChannelPopUp.removeAllItems()
        curveChannelPopUp.addItems(withTitles: ["Luma", "Red", "Green", "Blue"])
        curveChannelPopUp.target = self
        curveChannelPopUp.action = #selector(curveChannelChanged)
        curveEditor.onCurveChange = { [weak self] points in
            guard let self else { return }
            switch self.curveChannelPopUp.indexOfSelectedItem {
            case 1: self.curveRed = points
            case 2: self.curveGreen = points
            case 3: self.curveBlue = points
            default: self.curveLuma = points
            }
            self.session?.replaceParameters(self.parametersFromSliders)
        }

        hslChannelPopUp.removeAllItems()
        hslChannelPopUp.addItems(withTitles: ["Reds", "Oranges", "Yellows", "Greens", "Aquas", "Blues", "Purples", "Magentas"])
        hslChannelPopUp.target = self
        hslChannelPopUp.action = #selector(hslChannelChanged)
    }

    private func configureWhiteBalanceEyedropper() {
        whiteBalanceEyedropperButton.bezelStyle = .accessoryBarAction
        whiteBalanceEyedropperButton.isBordered = false
        whiteBalanceEyedropperButton.setButtonType(.toggle)
        whiteBalanceEyedropperButton.toolTip = "White Balance eyedropper"
        whiteBalanceEyedropperButton.target = self
        whiteBalanceEyedropperButton.action = #selector(whiteBalanceEyedropperPressed)
        if let image = NSImage(systemSymbolName: "eyedropper.halffull", accessibilityDescription: "White Balance eyedropper") {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            whiteBalanceEyedropperButton.image = image.withSymbolConfiguration(config)
            whiteBalanceEyedropperButton.image?.isTemplate = true
        }
        whiteBalanceEyedropperButton.contentTintColor = .secondaryLabelColor
        NSLayoutConstraint.activate([
            whiteBalanceEyedropperButton.widthAnchor.constraint(equalToConstant: 28),
            whiteBalanceEyedropperButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func installSemanticTrackChrome() {
        saturationSlider.applySemanticTrack(.saturation)
        vibranceSlider.applySemanticTrack(.vibrance)
        hueSlider.applySemanticTrack(.hue)
        temperatureSlider.applySemanticTrack(.temperature)
        tintSlider.applySemanticTrack(.tint)
        colorBalanceSlider.applySemanticTrack(.colorBalance)
        splitHighlightSlider.applySemanticTrack(.splitHighlight)
        splitShadowSlider.applySemanticTrack(.splitShadow)
        hslHueSlider.applySemanticTrack(.hue)
        hslSatSlider.applySemanticTrack(.saturation)
        blackAndWhiteSlider.applySemanticTrack(.blackAndWhiteAmount)
        bwWarmthSlider.applySemanticTrack(.blackAndWhiteWarmth)
    }

    @objc private func curveChannelChanged() {
        switch curveChannelPopUp.indexOfSelectedItem {
        case 1: curveEditor.setCurve(curveRed)
        case 2: curveEditor.setCurve(curveGreen)
        case 3: curveEditor.setCurve(curveBlue)
        default: curveEditor.setCurve(curveLuma)
        }
    }

    @objc private func hslChannelChanged() {
        let idx = max(0, min(ImageAdjustParameters.hslChannelCount - 1, hslChannelPopUp.indexOfSelectedItem))
        isPullingFromSession = true
        hslHueSlider.doubleValue = hslHue[idx]
        hslSatSlider.doubleValue = hslSat[idx]
        hslLumaSlider.doubleValue = hslLuma[idx]
        isPullingFromSession = false
        refreshValueLabels()
    }

    @objc private func whiteBalanceEyedropperPressed() {
        isWhiteBalanceEyedropperActive.toggle()
        refreshEyedropperChrome()
        onWhiteBalanceEyedropperToggle?(isWhiteBalanceEyedropperActive)
    }

    private func refreshEyedropperChrome() {
        whiteBalanceEyedropperButton.state = isWhiteBalanceEyedropperActive ? .on : .off
        whiteBalanceEyedropperButton.contentTintColor = isWhiteBalanceEyedropperActive
            ? LaughTheme.interactiveAccent
            : .secondaryLabelColor
    }

    /// Sync widgets from the session after presets / reset / external apply.
    func pullFromSession() {
        guard let session else { return }
        isPullingFromSession = true
        defer { isPullingFromSession = false }
        writeSliders(from: session.rawParameters)
        refreshValueLabels()
    }

    @objc private func sliderChanged(_ sender: Any?) {
        guard !isPullingFromSession else { return }
        // Keep HSL arrays in sync with the active channel sliders.
        let hslIdx = max(0, min(ImageAdjustParameters.hslChannelCount - 1, hslChannelPopUp.indexOfSelectedItem))
        hslHue[hslIdx] = hslHueSlider.doubleValue
        hslSat[hslIdx] = hslSatSlider.doubleValue
        hslLuma[hslIdx] = hslLumaSlider.doubleValue
        refreshValueLabels()
        // Double-click reset commits full quality; drag stays on the preview→settle path.
        if let event = NSApp.currentEvent, event.clickCount >= 2 {
            session?.apply(parametersFromSliders, quality: .full, clearBypasses: false)
        } else {
            session?.replaceParameters(parametersFromSliders)
        }
    }

    /// Identity values for double-click-on-knob reset (Lightroom-style).
    private func installParameterResetDefaults() {
        let identity = ImageAdjustParameters.identity
        exposureSlider.parameterResetValue = identity.exposure
        brightnessSlider.parameterResetValue = identity.brightness
        contrastSlider.parameterResetValue = identity.contrast
        smartContrastSlider.parameterResetValue = identity.smartContrast
        highlightsSlider.parameterResetValue = identity.highlights
        shadowsSlider.parameterResetValue = identity.shadows
        whitesSlider.parameterResetValue = identity.whites
        blacksSlider.parameterResetValue = identity.blacks
        saturationSlider.parameterResetValue = identity.saturation
        vibranceSlider.parameterResetValue = identity.vibrance
        hueSlider.parameterResetValue = identity.hue
        temperatureSlider.parameterResetValue = identity.temperature
        tintSlider.parameterResetValue = identity.tint
        colorBalanceSlider.parameterResetValue = identity.colorBalance
        splitHighlightSlider.parameterResetValue = identity.splitHighlight
        splitShadowSlider.parameterResetValue = identity.splitShadow
        splitAmountSlider.parameterResetValue = identity.splitAmount
        dramaticSlider.parameterResetValue = identity.dramatic
        moodSlider.parameterResetValue = identity.mood
        matteSlider.parameterResetValue = identity.matte
        glowSlider.parameterResetValue = identity.glow
        glowRadiusSlider.parameterResetValue = identity.glowRadius
        blurSlider.parameterResetValue = identity.blur
        filmGrainSlider.parameterResetValue = identity.filmGrain
        filmGrainSizeSlider.parameterResetValue = identity.filmGrainSize
        mysticalSlider.parameterResetValue = identity.mystical
        mysticalHazeSlider.parameterResetValue = identity.mysticalHaze
        mysticalHueSlider.parameterResetValue = identity.mysticalHue
        toningAmountSlider.parameterResetValue = identity.toningAmount
        toningHighlightsSlider.parameterResetValue = identity.toningHighlights
        toningShadowsSlider.parameterResetValue = identity.toningShadows
        highKeySlider.parameterResetValue = identity.highKey
        highKeySoftnessSlider.parameterResetValue = identity.highKeySoftness
        supercontrastSlider.parameterResetValue = identity.supercontrast
        supercontrastMidtonesSlider.parameterResetValue = identity.supercontrastMidtones
        colorHarmonySlider.parameterResetValue = identity.colorHarmony
        colorHarmonyBalanceSlider.parameterResetValue = identity.colorHarmonyBalance
        sunraysSlider.parameterResetValue = identity.sunrays
        sunraysLengthSlider.parameterResetValue = identity.sunraysLength
        sunraysWarmthSlider.parameterResetValue = identity.sunraysWarmth
        landscapeSlider.parameterResetValue = identity.landscape
        landscapeFoliageSlider.parameterResetValue = identity.landscapeFoliage
        landscapeSkySlider.parameterResetValue = identity.landscapeSky
        blackAndWhiteSlider.parameterResetValue = identity.blackAndWhite
        bwContrastSlider.parameterResetValue = identity.bwContrast
        bwWarmthSlider.parameterResetValue = identity.bwWarmth
        sharpnessSlider.parameterResetValue = identity.sharpness
        sharpenRadiusSlider.parameterResetValue = identity.sharpenRadius
        sharpenDetailSlider.parameterResetValue = identity.sharpenDetail
        definitionSlider.parameterResetValue = identity.definition
        structureSlider.parameterResetValue = identity.structure
        denoiseSlider.parameterResetValue = identity.denoise
        denoiseColorSlider.parameterResetValue = identity.denoiseColor
        denoiseDetailSlider.parameterResetValue = identity.denoiseDetail
        hslHueSlider.parameterResetValue = 0
        hslSatSlider.parameterResetValue = 0
        hslLumaSlider.parameterResetValue = 0
        vignetteSlider.parameterResetValue = identity.vignette
        vignetteMidpointSlider.parameterResetValue = identity.vignetteMidpoint
        vignetteCenterXSlider.parameterResetValue = identity.vignetteCenterX
        vignetteCenterYSlider.parameterResetValue = identity.vignetteCenterY
        dodgeBurnSlider.parameterResetValue = identity.dodgeBurn
        dodgeBurnRangeSlider.parameterResetValue = identity.dodgeBurnRange
        dodgeBurnSoftnessSlider.parameterResetValue = identity.dodgeBurnSoftness
        distortionSlider.parameterResetValue = identity.distortion
        chromaticAberrationSlider.parameterResetValue = identity.chromaticAberration
        defringePurpleSlider.parameterResetValue = identity.defringePurple
        defringeGreenSlider.parameterResetValue = identity.defringeGreen
    }

    private func writeSliders(from parameters: ImageAdjustParameters) {
        exposureSlider.doubleValue = parameters.exposure
        brightnessSlider.doubleValue = parameters.brightness
        contrastSlider.doubleValue = parameters.contrast
        smartContrastSlider.doubleValue = parameters.smartContrast
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
        curveLuma = parameters.curveLuma
        curveRed = parameters.curveRed
        curveGreen = parameters.curveGreen
        curveBlue = parameters.curveBlue
        hslHue = parameters.hslHue
        hslSat = parameters.hslSat
        hslLuma = parameters.hslLuma
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
        sharpenRadiusSlider.doubleValue = parameters.sharpenRadius
        sharpenDetailSlider.doubleValue = parameters.sharpenDetail
        definitionSlider.doubleValue = parameters.definition
        structureSlider.doubleValue = parameters.structure
        denoiseSlider.doubleValue = parameters.denoise
        denoiseColorSlider.doubleValue = parameters.denoiseColor
        denoiseDetailSlider.doubleValue = parameters.denoiseDetail
        vignetteSlider.doubleValue = parameters.vignette
        vignetteMidpointSlider.doubleValue = parameters.vignetteMidpoint
        vignetteCenterXSlider.doubleValue = parameters.vignetteCenterX
        vignetteCenterYSlider.doubleValue = parameters.vignetteCenterY
        dodgeBurnSlider.doubleValue = parameters.dodgeBurn
        dodgeBurnRangeSlider.doubleValue = parameters.dodgeBurnRange
        dodgeBurnSoftnessSlider.doubleValue = parameters.dodgeBurnSoftness
        distortionSlider.doubleValue = parameters.distortion
        chromaticAberrationSlider.doubleValue = parameters.chromaticAberration
        defringePurpleSlider.doubleValue = parameters.defringePurple
        defringeGreenSlider.doubleValue = parameters.defringeGreen
        curveChannelChanged()
        hslChannelChanged()
    }

    private func refreshValueLabels() {
        exposureValueLabel.stringValue = String(format: "%+.2f", exposureSlider.doubleValue)
        brightnessValueLabel.stringValue = String(format: "%+.2f", brightnessSlider.doubleValue)
        contrastValueLabel.stringValue = String(format: "%.2f", contrastSlider.doubleValue)
        smartContrastValueLabel.stringValue = String(format: "%.2f", smartContrastSlider.doubleValue)
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
        sharpenRadiusValueLabel.stringValue = String(format: "%.2f", sharpenRadiusSlider.doubleValue)
        sharpenDetailValueLabel.stringValue = String(format: "%.2f", sharpenDetailSlider.doubleValue)
        definitionValueLabel.stringValue = String(format: "%+.2f", definitionSlider.doubleValue)
        structureValueLabel.stringValue = String(format: "%+.2f", structureSlider.doubleValue)
        denoiseValueLabel.stringValue = String(format: "%.2f", denoiseSlider.doubleValue)
        denoiseColorValueLabel.stringValue = String(format: "%.2f", denoiseColorSlider.doubleValue)
        denoiseDetailValueLabel.stringValue = String(format: "%.2f", denoiseDetailSlider.doubleValue)
        hslHueValueLabel.stringValue = String(format: "%+.2f", hslHueSlider.doubleValue)
        hslSatValueLabel.stringValue = String(format: "%+.2f", hslSatSlider.doubleValue)
        hslLumaValueLabel.stringValue = String(format: "%+.2f", hslLumaSlider.doubleValue)
        vignetteValueLabel.stringValue = String(format: "%.2f", vignetteSlider.doubleValue)
        vignetteMidpointValueLabel.stringValue = String(format: "%.2f", vignetteMidpointSlider.doubleValue)
        vignetteCenterXValueLabel.stringValue = String(format: "%.2f", vignetteCenterXSlider.doubleValue)
        vignetteCenterYValueLabel.stringValue = String(format: "%.2f", vignetteCenterYSlider.doubleValue)
        dodgeBurnValueLabel.stringValue = String(format: "%+.2f", dodgeBurnSlider.doubleValue)
        dodgeBurnRangeValueLabel.stringValue = String(format: "%+.2f", dodgeBurnRangeSlider.doubleValue)
        dodgeBurnSoftnessValueLabel.stringValue = String(format: "%.2f", dodgeBurnSoftnessSlider.doubleValue)
        distortionValueLabel.stringValue = String(format: "%+.2f", distortionSlider.doubleValue)
        chromaticAberrationValueLabel.stringValue = String(format: "%.2f", chromaticAberrationSlider.doubleValue)
        defringePurpleValueLabel.stringValue = String(format: "%.2f", defringePurpleSlider.doubleValue)
        defringeGreenValueLabel.stringValue = String(format: "%.2f", defringeGreenSlider.doubleValue)
    }
}
