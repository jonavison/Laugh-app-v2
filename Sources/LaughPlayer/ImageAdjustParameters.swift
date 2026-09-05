import CoreImage
import Foundation

/// Expandable Edits tools that own a subset of `ImageAdjustParameters`.
enum ImageAdjustSection: String, CaseIterable, Hashable {
    case develop
    case color
    case dramatic
    case mood
    case toning
    case matte
    case glow
    case blur
    case filmGrain
    case mystical
    case highKey
    case supercontrast
    case colorHarmony
    case sunrays
    case landscape
    case blackAndWhite
    case details
    case denoise
    case vignette
    case dodgeBurn

    var title: String {
        switch self {
        case .develop: return "Develop"
        case .color: return "Color"
        case .dramatic: return "Dramatic"
        case .mood: return "Mood"
        case .toning: return "Toning"
        case .matte: return "Matte"
        case .glow: return "Glow"
        case .blur: return "Blur"
        case .filmGrain: return "Film Grain"
        case .mystical: return "Mystical"
        case .highKey: return "High Key"
        case .supercontrast: return "Supercontrast"
        case .colorHarmony: return "Color Harmony"
        case .sunrays: return "Sunrays"
        case .landscape: return "Landscape"
        case .blackAndWhite: return "Black & White"
        case .details: return "Details"
        case .denoise: return "Denoise"
        case .dodgeBurn: return "Dodge & Burn"
        case .vignette: return "Vignette"
        }
    }
}

/// Shared display-only develop parameters for **ImageMedia** (see ADR 0004).
struct ImageAdjustParameters: Equatable, Codable {
    // Light
    var exposure: Double
    var brightness: Double
    var contrast: Double
    var highlights: Double
    var shadows: Double
    var whites: Double
    var blacks: Double

    // Color
    var saturation: Double
    var vibrance: Double
    var hue: Double
    var temperature: Double
    var tint: Double
    var colorBalance: Double
    var splitHighlight: Double
    var splitShadow: Double
    var splitAmount: Double
    var dramatic: Double
    var mood: Double
    var matte: Double
    var glow: Double
    var glowRadius: Double
    var blur: Double
    var filmGrain: Double
    var filmGrainSize: Double
    var mystical: Double
    var mysticalHaze: Double
    var mysticalHue: Double
    var toningAmount: Double
    var toningHighlights: Double
    var toningShadows: Double
    var highKey: Double
    var highKeySoftness: Double
    var supercontrast: Double
    var supercontrastMidtones: Double
    var colorHarmony: Double
    var colorHarmonyBalance: Double
    var sunrays: Double
    var sunraysLength: Double
    var sunraysWarmth: Double
    var landscape: Double
    var landscapeFoliage: Double
    var landscapeSky: Double
    var blackAndWhite: Double
    var bwContrast: Double
    var bwWarmth: Double

    // Detail
    var sharpness: Double
    var definition: Double
    var structure: Double
    var denoise: Double

    // Effects
    var vignette: Double
    var vignetteMidpoint: Double
    var dodgeBurn: Double
    var dodgeBurnRange: Double
    var dodgeBurnSoftness: Double

    init(
        exposure: Double = 0,
        brightness: Double = 0,
        contrast: Double = 1,
        highlights: Double = 1,
        shadows: Double = 0,
        whites: Double = 0,
        blacks: Double = 0,
        saturation: Double = 1,
        vibrance: Double = 0,
        hue: Double = 0,
        temperature: Double = 0,
        tint: Double = 0,
        colorBalance: Double = 0,
        splitHighlight: Double = 0,
        splitShadow: Double = 0,
        splitAmount: Double = 0,
        dramatic: Double = 0,
        mood: Double = 0,
        matte: Double = 0,
        glow: Double = 0,
        glowRadius: Double = 0.45,
        blur: Double = 0,
        filmGrain: Double = 0,
        filmGrainSize: Double = 0.45,
        mystical: Double = 0,
        mysticalHaze: Double = 0.4,
        mysticalHue: Double = -0.25,
        toningAmount: Double = 0,
        toningHighlights: Double = 0,
        toningShadows: Double = 0,
        highKey: Double = 0,
        highKeySoftness: Double = 0.35,
        supercontrast: Double = 0,
        supercontrastMidtones: Double = 0.5,
        colorHarmony: Double = 0,
        colorHarmonyBalance: Double = 0.15,
        sunrays: Double = 0,
        sunraysLength: Double = 0.55,
        sunraysWarmth: Double = 0.45,
        landscape: Double = 0,
        landscapeFoliage: Double = 0.55,
        landscapeSky: Double = 0.45,
        blackAndWhite: Double = 0,
        bwContrast: Double = 0.15,
        bwWarmth: Double = 0,
        sharpness: Double = 0,
        definition: Double = 0,
        structure: Double = 0,
        denoise: Double = 0,
        vignette: Double = 0,
        vignetteMidpoint: Double = 0.5,
        dodgeBurn: Double = 0,
        dodgeBurnRange: Double = 0,
        dodgeBurnSoftness: Double = 0.45
    ) {
        self.exposure = exposure
        self.brightness = brightness
        self.contrast = contrast
        self.highlights = highlights
        self.shadows = shadows
        self.whites = whites
        self.blacks = blacks
        self.saturation = saturation
        self.vibrance = vibrance
        self.hue = hue
        self.temperature = temperature
        self.tint = tint
        self.colorBalance = colorBalance
        self.splitHighlight = splitHighlight
        self.splitShadow = splitShadow
        self.splitAmount = splitAmount
        self.dramatic = dramatic
        self.mood = mood
        self.matte = matte
        self.glow = glow
        self.glowRadius = glowRadius
        self.blur = blur
        self.filmGrain = filmGrain
        self.filmGrainSize = filmGrainSize
        self.mystical = mystical
        self.mysticalHaze = mysticalHaze
        self.mysticalHue = mysticalHue
        self.toningAmount = toningAmount
        self.toningHighlights = toningHighlights
        self.toningShadows = toningShadows
        self.highKey = highKey
        self.highKeySoftness = highKeySoftness
        self.supercontrast = supercontrast
        self.supercontrastMidtones = supercontrastMidtones
        self.colorHarmony = colorHarmony
        self.colorHarmonyBalance = colorHarmonyBalance
        self.sunrays = sunrays
        self.sunraysLength = sunraysLength
        self.sunraysWarmth = sunraysWarmth
        self.landscape = landscape
        self.landscapeFoliage = landscapeFoliage
        self.landscapeSky = landscapeSky
        self.blackAndWhite = blackAndWhite
        self.bwContrast = bwContrast
        self.bwWarmth = bwWarmth
        self.sharpness = sharpness
        self.definition = definition
        self.structure = structure
        self.denoise = denoise
        self.vignette = vignette
        self.vignetteMidpoint = vignetteMidpoint
        self.dodgeBurn = dodgeBurn
        self.dodgeBurnRange = dodgeBurnRange
        self.dodgeBurnSoftness = dodgeBurnSoftness
    }

    static let identity = ImageAdjustParameters()

    var isIdentity: Bool {
        ImageAdjustSection.allCases.allSatisfy { !isEdited($0) }
    }

    /// Whether any control in the section differs from identity defaults.
    func isEdited(_ section: ImageAdjustSection) -> Bool {
        let id = Self.identity
        switch section {
        case .develop:
            return !near(exposure, id.exposure)
                || !near(brightness, id.brightness)
                || !near(contrast, id.contrast)
                || !near(highlights, id.highlights)
                || !near(shadows, id.shadows)
                || !near(whites, id.whites)
                || !near(blacks, id.blacks)
        case .color:
            return !near(saturation, id.saturation)
                || !near(vibrance, id.vibrance)
                || !near(hue, id.hue)
                || !near(temperature, id.temperature)
                || !near(tint, id.tint)
                || !near(colorBalance, id.colorBalance)
                || !near(splitHighlight, id.splitHighlight)
                || !near(splitShadow, id.splitShadow)
                || !near(splitAmount, id.splitAmount)
        case .dramatic:
            return !near(dramatic, id.dramatic)
        case .mood:
            return !near(mood, id.mood)
        case .matte:
            return !near(matte, id.matte)
        case .glow:
            return !near(glow, id.glow) || !near(glowRadius, id.glowRadius)
        case .blur:
            return !near(blur, id.blur)
        case .filmGrain:
            return !near(filmGrain, id.filmGrain) || !near(filmGrainSize, id.filmGrainSize)
        case .mystical:
            return !near(mystical, id.mystical)
                || !near(mysticalHaze, id.mysticalHaze)
                || !near(mysticalHue, id.mysticalHue)
        case .toning:
            return !near(toningAmount, id.toningAmount)
                || !near(toningHighlights, id.toningHighlights)
                || !near(toningShadows, id.toningShadows)
        case .highKey:
            return !near(highKey, id.highKey) || !near(highKeySoftness, id.highKeySoftness)
        case .supercontrast:
            return !near(supercontrast, id.supercontrast)
                || !near(supercontrastMidtones, id.supercontrastMidtones)
        case .colorHarmony:
            return !near(colorHarmony, id.colorHarmony)
                || !near(colorHarmonyBalance, id.colorHarmonyBalance)
        case .sunrays:
            return !near(sunrays, id.sunrays)
                || !near(sunraysLength, id.sunraysLength)
                || !near(sunraysWarmth, id.sunraysWarmth)
        case .landscape:
            return !near(landscape, id.landscape)
                || !near(landscapeFoliage, id.landscapeFoliage)
                || !near(landscapeSky, id.landscapeSky)
        case .blackAndWhite:
            return !near(blackAndWhite, id.blackAndWhite)
                || !near(bwContrast, id.bwContrast)
                || !near(bwWarmth, id.bwWarmth)
        case .details:
            return !near(sharpness, id.sharpness)
                || !near(definition, id.definition)
                || !near(structure, id.structure)
        case .denoise:
            return !near(denoise, id.denoise)
        case .vignette:
            return !near(vignette, id.vignette) || !near(vignetteMidpoint, id.vignetteMidpoint)
        case .dodgeBurn:
            return !near(dodgeBurn, id.dodgeBurn)
                || !near(dodgeBurnRange, id.dodgeBurnRange)
                || !near(dodgeBurnSoftness, id.dodgeBurnSoftness)
        }
    }

    /// Reset one Edits section to identity; leave other sections unchanged.
    func resetting(_ section: ImageAdjustSection) -> ImageAdjustParameters {
        var next = self
        let id = Self.identity
        switch section {
        case .develop:
            next.exposure = id.exposure
            next.brightness = id.brightness
            next.contrast = id.contrast
            next.highlights = id.highlights
            next.shadows = id.shadows
            next.whites = id.whites
            next.blacks = id.blacks
        case .color:
            next.saturation = id.saturation
            next.vibrance = id.vibrance
            next.hue = id.hue
            next.temperature = id.temperature
            next.tint = id.tint
            next.colorBalance = id.colorBalance
            next.splitHighlight = id.splitHighlight
            next.splitShadow = id.splitShadow
            next.splitAmount = id.splitAmount
        case .dramatic:
            next.dramatic = id.dramatic
        case .mood:
            next.mood = id.mood
        case .matte:
            next.matte = id.matte
        case .glow:
            next.glow = id.glow
            next.glowRadius = id.glowRadius
        case .blur:
            next.blur = id.blur
        case .filmGrain:
            next.filmGrain = id.filmGrain
            next.filmGrainSize = id.filmGrainSize
        case .mystical:
            next.mystical = id.mystical
            next.mysticalHaze = id.mysticalHaze
            next.mysticalHue = id.mysticalHue
        case .toning:
            next.toningAmount = id.toningAmount
            next.toningHighlights = id.toningHighlights
            next.toningShadows = id.toningShadows
        case .highKey:
            next.highKey = id.highKey
            next.highKeySoftness = id.highKeySoftness
        case .supercontrast:
            next.supercontrast = id.supercontrast
            next.supercontrastMidtones = id.supercontrastMidtones
        case .colorHarmony:
            next.colorHarmony = id.colorHarmony
            next.colorHarmonyBalance = id.colorHarmonyBalance
        case .sunrays:
            next.sunrays = id.sunrays
            next.sunraysLength = id.sunraysLength
            next.sunraysWarmth = id.sunraysWarmth
        case .landscape:
            next.landscape = id.landscape
            next.landscapeFoliage = id.landscapeFoliage
            next.landscapeSky = id.landscapeSky
        case .blackAndWhite:
            next.blackAndWhite = id.blackAndWhite
            next.bwContrast = id.bwContrast
            next.bwWarmth = id.bwWarmth
        case .details:
            next.sharpness = id.sharpness
            next.definition = id.definition
            next.structure = id.structure
        case .denoise:
            next.denoise = id.denoise
        case .vignette:
            next.vignette = id.vignette
            next.vignetteMidpoint = id.vignetteMidpoint
        case .dodgeBurn:
            next.dodgeBurn = id.dodgeBurn
            next.dodgeBurnRange = id.dodgeBurnRange
            next.dodgeBurnSoftness = id.dodgeBurnSoftness
        }
        return next
    }

    /// Temporarily treat bypassed sections as identity (section before/after).
    func bypassing(_ sections: Set<ImageAdjustSection>) -> ImageAdjustParameters {
        guard !sections.isEmpty else { return self }
        var next = self
        for section in sections {
            next = next.resetting(section)
        }
        return next
    }

    private func near(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.001
    }

    /// Apply the develop chain. Returns `nil` when identity (caller keeps original).
    /// Order is tonal → color → clean → detail → vignette for stable preview quality.
    func applying(to ciImage: CIImage) -> CIImage? {
        guard !isIdentity else { return nil }
        var current = ciImage

        if abs(exposure) >= 0.001, let filter = CIFilter(name: "CIExposureAdjust") {
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(NSNumber(value: exposure), forKey: kCIInputEVKey)
            if let out = filter.outputImage { current = out }
        }

        if abs(highlights - 1) >= 0.001 || abs(shadows) >= 0.001,
           let filter = CIFilter(name: "CIHighlightShadowAdjust") {
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(NSNumber(value: highlights), forKey: "inputHighlightAmount")
            filter.setValue(NSNumber(value: shadows), forKey: "inputShadowAmount")
            if let out = filter.outputImage { current = out }
        }

        if abs(whites) >= 0.001 || abs(blacks) >= 0.001,
           let filter = CIFilter(name: "CIToneCurve") {
            let blackY = max(0, min(0.35, 0.0 + blacks * 0.22))
            let whiteY = max(0.65, min(1.0, 1.0 + whites * 0.22))
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(CIVector(x: 0, y: CGFloat(blackY)), forKey: "inputPoint0")
            filter.setValue(CIVector(x: 0.25, y: 0.25 + CGFloat(blacks) * 0.04), forKey: "inputPoint1")
            filter.setValue(CIVector(x: 0.5, y: 0.5), forKey: "inputPoint2")
            filter.setValue(CIVector(x: 0.75, y: 0.75 + CGFloat(whites) * 0.04), forKey: "inputPoint3")
            filter.setValue(CIVector(x: 1, y: CGFloat(whiteY)), forKey: "inputPoint4")
            if let out = filter.outputImage { current = out }
        }

        let effectiveSaturation = max(0, saturation * (1 - max(0, min(1, blackAndWhite))))
        if abs(brightness) >= 0.001 || abs(contrast - 1) >= 0.001 || abs(effectiveSaturation - 1) >= 0.001,
           let filter = CIFilter(name: "CIColorControls") {
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(NSNumber(value: brightness), forKey: kCIInputBrightnessKey)
            filter.setValue(NSNumber(value: contrast), forKey: kCIInputContrastKey)
            filter.setValue(NSNumber(value: effectiveSaturation), forKey: kCIInputSaturationKey)
            if let out = filter.outputImage { current = out }
        }

        if blackAndWhite > 0.001 {
            current = applyBlackAndWhiteLook(
                to: current,
                amount: blackAndWhite,
                contrast: bwContrast,
                warmth: bwWarmth
            )
        }

        if abs(vibrance) >= 0.001, blackAndWhite < 0.98, let filter = CIFilter(name: "CIVibrance") {
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(NSNumber(value: vibrance * (1 - blackAndWhite)), forKey: "inputAmount")
            if let out = filter.outputImage { current = out }
        }

        if abs(hue) >= 0.001, blackAndWhite < 0.98, let filter = CIFilter(name: "CIHueAdjust") {
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(NSNumber(value: hue * .pi), forKey: kCIInputAngleKey)
            if let out = filter.outputImage { current = out }
        }

        if abs(temperature) >= 0.001 || abs(tint) >= 0.001,
           let filter = CIFilter(name: "CITemperatureAndTint") {
            let neutral = CIVector(x: 6500, y: 0)
            let target = CIVector(x: 6500 + CGFloat(temperature) * 2500, y: CGFloat(tint) * 100)
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(neutral, forKey: "inputNeutral")
            filter.setValue(target, forKey: "inputTargetNeutral")
            if let out = filter.outputImage { current = out }
        }

        if abs(colorBalance) >= 0.001, blackAndWhite < 0.98,
           let filter = CIFilter(name: "CIColorMatrix") {
            let shift = CGFloat(colorBalance) * 0.12
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(CIVector(x: 1 + shift, y: 0, z: 0, w: 0), forKey: "inputRVector")
            filter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
            filter.setValue(CIVector(x: 0, y: 0, z: 1 - shift, w: 0), forKey: "inputBVector")
            filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            if let out = filter.outputImage { current = out }
        }

        if abs(splitAmount) >= 0.001, blackAndWhite < 0.98 {
            current = applySplitTone(to: current)
        }

        if dramatic > 0.001 {
            current = applyDramatic(to: current, amount: dramatic)
        }

        if mood > 0.001 {
            current = applyMood(to: current, amount: mood)
        }

        if toningAmount > 0.001 {
            current = applyCreativeToning(to: current)
        }

        if matte > 0.001 {
            current = applyMatte(to: current, amount: matte)
        }

        if highKey > 0.001 {
            current = applyHighKey(to: current, amount: highKey, softness: highKeySoftness)
        }

        if supercontrast > 0.001 {
            current = applySupercontrast(to: current, amount: supercontrast, midtones: supercontrastMidtones)
        }

        if mystical > 0.001 {
            current = applyMystical(to: current, amount: mystical, haze: mysticalHaze, hue: mysticalHue)
        }

        if colorHarmony > 0.001 {
            current = applyColorHarmony(to: current, amount: colorHarmony, balance: colorHarmonyBalance)
        }

        if landscape > 0.001 {
            current = applyLandscape(to: current, amount: landscape, foliage: landscapeFoliage, sky: landscapeSky)
        }

        if denoise > 0.001, let filter = CIFilter(name: "CINoiseReduction") {
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(NSNumber(value: denoise * 0.08), forKey: "inputNoiseLevel")
            filter.setValue(NSNumber(value: 0.35 + denoise * 0.4), forKey: "inputSharpness")
            if let out = filter.outputImage { current = out }
        }

        if abs(structure) >= 0.001, let filter = CIFilter(name: "CIUnsharpMask") {
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(NSNumber(value: 2.4), forKey: kCIInputRadiusKey)
            filter.setValue(NSNumber(value: structure * 0.55), forKey: kCIInputIntensityKey)
            if let out = filter.outputImage { current = out }
        }

        if abs(definition) >= 0.001, let filter = CIFilter(name: "CIUnsharpMask") {
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(NSNumber(value: 1.4), forKey: kCIInputRadiusKey)
            filter.setValue(NSNumber(value: definition * 0.65), forKey: kCIInputIntensityKey)
            if let out = filter.outputImage { current = out }
        }

        if sharpness > 0.001, let filter = CIFilter(name: "CISharpenLuminance") {
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(NSNumber(value: sharpness * 0.85), forKey: kCIInputSharpnessKey)
            if let out = filter.outputImage { current = out }
        }

        if abs(dodgeBurn) > 0.001 {
            current = applyDodgeBurn(
                to: current,
                amount: dodgeBurn,
                range: dodgeBurnRange,
                softness: dodgeBurnSoftness
            )
        }

        if glow > 0.001 {
            current = applyGlow(to: current, amount: glow, radius: glowRadius)
        }

        if sunrays > 0.001 {
            current = applySunrays(to: current, amount: sunrays, length: sunraysLength, warmth: sunraysWarmth)
        }

        if vignette > 0.001, let filter = CIFilter(name: "CIVignette") {
            let mid = max(0, min(1, vignetteMidpoint))
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(NSNumber(value: vignette * 1.35), forKey: kCIInputIntensityKey)
            // Higher midpoint keeps a larger clear center (darkening hugs the edges).
            filter.setValue(NSNumber(value: 0.55 + mid * 1.55 + vignette * 0.25), forKey: kCIInputRadiusKey)
            if let out = filter.outputImage { current = out }
        }

        if blur > 0.001 {
            current = applySoftFocus(to: current, amount: blur)
        }

        if filmGrain > 0.001 {
            current = applyFilmGrain(to: current, amount: filmGrain, size: filmGrainSize)
        }

        return current
    }

    /// Mono polish: contrast lift + cool/warm silver tone scaled by Amount.
    private func applyBlackAndWhiteLook(
        to image: CIImage,
        amount: Double,
        contrast: Double,
        warmth: Double
    ) -> CIImage {
        let a = max(0, min(1, amount))
        guard a > 0.001 else { return image }
        var current = image
        let extent = image.extent

        if abs(contrast) >= 0.001 || a > 0.2, let controls = CIFilter(name: "CIColorControls") {
            controls.setValue(current, forKey: kCIInputImageKey)
            controls.setValue(NSNumber(value: 1 + contrast * 0.5 * a + 0.06 * a), forKey: kCIInputContrastKey)
            controls.setValue(NSNumber(value: -0.02 * a), forKey: kCIInputBrightnessKey)
            if let out = controls.outputImage { current = out }
        }

        if abs(warmth) >= 0.001, let matrix = CIFilter(name: "CIColorMatrix") {
            let w = CGFloat(warmth) * CGFloat(a) * 0.2
            matrix.setValue(current, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 1 + 0.55 * w, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: 1 + 0.2 * w, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 1 - 0.45 * w, w: 0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            if let out = matrix.outputImage { current = out.cropped(to: extent) }
        }

        return current
    }

    /// Tonal-range dodge/burn via luminosity mask (brush painting deferred).
    private func applyDodgeBurn(
        to image: CIImage,
        amount: Double,
        range: Double,
        softness: Double
    ) -> CIImage {
        let amt = max(-1, min(1, amount))
        guard abs(amt) > 0.001 else { return image }
        let extent = image.extent
        let center = 0.5 + max(-1, min(1, range)) * 0.38
        let soft = max(0.05, min(1, softness))
        let width = 0.16 + soft * 0.44

        // Rec.709 luminance → RGB for tone-curve masking.
        guard let lumaMatrix = CIFilter(name: "CIColorMatrix") else { return image }
        lumaMatrix.setValue(image, forKey: kCIInputImageKey)
        lumaMatrix.setValue(CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0), forKey: "inputRVector")
        lumaMatrix.setValue(CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0), forKey: "inputGVector")
        lumaMatrix.setValue(CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0), forKey: "inputBVector")
        lumaMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        guard var softMask = lumaMatrix.outputImage?.cropped(to: extent) else { return image }

        // Soft tent peak around `center` (shadows ← midtones → highlights).
        if let curve = CIFilter(name: "CIToneCurve") {
            let lo = max(0, center - width)
            let hi = min(1, center + width)
            let yAt: (Double) -> CGFloat = { x in
                let d = abs(x - center) / max(width, 0.001)
                let m = max(0, 1 - d)
                return CGFloat(m * m * (3 - 2 * m))
            }
            curve.setValue(softMask, forKey: kCIInputImageKey)
            curve.setValue(CIVector(x: 0, y: yAt(0)), forKey: "inputPoint0")
            curve.setValue(CIVector(x: CGFloat(lo), y: yAt(lo)), forKey: "inputPoint1")
            curve.setValue(CIVector(x: CGFloat(center), y: 1), forKey: "inputPoint2")
            curve.setValue(CIVector(x: CGFloat(hi), y: yAt(hi)), forKey: "inputPoint3")
            curve.setValue(CIVector(x: 1, y: yAt(1)), forKey: "inputPoint4")
            if let out = curve.outputImage?.cropped(to: extent) { softMask = out }
        }

        if soft > 0.08, let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(softMask, forKey: kCIInputImageKey)
            blur.setValue(NSNumber(value: 1.5 + soft * 16), forKey: kCIInputRadiusKey)
            if let out = blur.outputImage?.cropped(to: extent) { softMask = out }
        }

        guard let exposure = CIFilter(name: "CIExposureAdjust") else { return image }
        // Positive Amount burns (darkens); negative dodges (lightens).
        exposure.setValue(image, forKey: kCIInputImageKey)
        exposure.setValue(NSNumber(value: -amt * 0.9), forKey: kCIInputEVKey)
        guard var target = exposure.outputImage?.cropped(to: extent) else { return image }

        if abs(amt) > 0.12, let usm = CIFilter(name: "CIUnsharpMask") {
            usm.setValue(target, forKey: kCIInputImageKey)
            usm.setValue(NSNumber(value: 1.8), forKey: kCIInputRadiusKey)
            usm.setValue(NSNumber(value: abs(amt) * 0.2), forKey: kCIInputIntensityKey)
            if let out = usm.outputImage?.cropped(to: extent) { target = out }
        }

        guard let blend = CIFilter(name: "CIBlendWithMask") else { return image }
        blend.setValue(target, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        blend.setValue(softMask, forKey: kCIInputMaskImageKey)
        return blend.outputImage?.cropped(to: extent) ?? image
    }

    /// Cinematic punch: S-curve, local contrast, cool shadows, restrained vignette.
    private func applyDramatic(to image: CIImage, amount: Double) -> CIImage {
        let s = max(0, min(1, amount))
        var current = image

        if let curve = CIFilter(name: "CIToneCurve") {
            let punch = CGFloat(s)
            curve.setValue(current, forKey: kCIInputImageKey)
            curve.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
            curve.setValue(CIVector(x: 0.22, y: 0.22 - 0.08 * punch), forKey: "inputPoint1")
            curve.setValue(CIVector(x: 0.5, y: 0.5 + 0.02 * punch), forKey: "inputPoint2")
            curve.setValue(CIVector(x: 0.78, y: 0.78 + 0.07 * punch), forKey: "inputPoint3")
            curve.setValue(CIVector(x: 1, y: 1), forKey: "inputPoint4")
            if let out = curve.outputImage { current = out }
        }

        if let tonal = CIFilter(name: "CIHighlightShadowAdjust") {
            tonal.setValue(current, forKey: kCIInputImageKey)
            tonal.setValue(NSNumber(value: 1 - 0.28 * s), forKey: "inputHighlightAmount")
            tonal.setValue(NSNumber(value: -0.18 * s), forKey: "inputShadowAmount")
            if let out = tonal.outputImage { current = out }
        }

        if let local = CIFilter(name: "CIUnsharpMask") {
            local.setValue(current, forKey: kCIInputImageKey)
            local.setValue(NSNumber(value: 3.2), forKey: kCIInputRadiusKey)
            local.setValue(NSNumber(value: 0.22 * s), forKey: kCIInputIntensityKey)
            if let out = local.outputImage { current = out }
        }

        if let color = CIFilter(name: "CIColorControls") {
            color.setValue(current, forKey: kCIInputImageKey)
            color.setValue(NSNumber(value: -0.025 * s), forKey: kCIInputBrightnessKey)
            color.setValue(NSNumber(value: 1 + 0.18 * s), forKey: kCIInputContrastKey)
            color.setValue(NSNumber(value: max(0, 1 - 0.12 * s)), forKey: kCIInputSaturationKey)
            if let out = color.outputImage { current = out }
        }

        if let temp = CIFilter(name: "CITemperatureAndTint") {
            temp.setValue(current, forKey: kCIInputImageKey)
            temp.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            temp.setValue(CIVector(x: 6500 - 380 * s, y: 18 * s), forKey: "inputTargetNeutral")
            if let out = temp.outputImage { current = out }
        }

        if let vig = CIFilter(name: "CIVignette") {
            vig.setValue(current, forKey: kCIInputImageKey)
            vig.setValue(NSNumber(value: 0.55 * s), forKey: kCIInputIntensityKey)
            vig.setValue(NSNumber(value: 1.35 + 0.4 * s), forKey: kCIInputRadiusKey)
            if let out = vig.outputImage { current = out }
        }
        return current
    }

    /// Soft nostalgic grade: lifted shadows, warm midtones, gentle highlight roll-off.
    private func applyMood(to image: CIImage, amount: Double) -> CIImage {
        let s = max(0, min(1, amount))
        var current = image

        if let curve = CIFilter(name: "CIToneCurve") {
            let lift = CGFloat(s)
            curve.setValue(current, forKey: kCIInputImageKey)
            curve.setValue(CIVector(x: 0, y: 0.05 * lift), forKey: "inputPoint0")
            curve.setValue(CIVector(x: 0.25, y: 0.28 + 0.04 * lift), forKey: "inputPoint1")
            curve.setValue(CIVector(x: 0.5, y: 0.52), forKey: "inputPoint2")
            curve.setValue(CIVector(x: 0.78, y: 0.74 - 0.04 * lift), forKey: "inputPoint3")
            curve.setValue(CIVector(x: 1, y: 0.96 - 0.03 * lift), forKey: "inputPoint4")
            if let out = curve.outputImage { current = out }
        }

        if let tonal = CIFilter(name: "CIHighlightShadowAdjust") {
            tonal.setValue(current, forKey: kCIInputImageKey)
            tonal.setValue(NSNumber(value: 1 - 0.32 * s), forKey: "inputHighlightAmount")
            tonal.setValue(NSNumber(value: 0.22 * s), forKey: "inputShadowAmount")
            if let out = tonal.outputImage { current = out }
        }

        if let color = CIFilter(name: "CIColorControls") {
            color.setValue(current, forKey: kCIInputImageKey)
            color.setValue(NSNumber(value: 0.04 * s), forKey: kCIInputBrightnessKey)
            color.setValue(NSNumber(value: 1 - 0.12 * s), forKey: kCIInputContrastKey)
            color.setValue(NSNumber(value: max(0, 1 - 0.16 * s)), forKey: kCIInputSaturationKey)
            if let out = color.outputImage { current = out }
        }

        if let temp = CIFilter(name: "CITemperatureAndTint") {
            temp.setValue(current, forKey: kCIInputImageKey)
            temp.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            temp.setValue(CIVector(x: 6500 + 780 * s, y: 55 * s), forKey: "inputTargetNeutral")
            if let out = temp.outputImage { current = out }
        }

        if let matrix = CIFilter(name: "CIColorMatrix") {
            let wash = CGFloat(s) * 0.14
            matrix.setValue(current, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 1 + 0.18 * wash, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: 1 + 0.05 * wash, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 1 - 0.1 * wash, w: 0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            if let out = matrix.outputImage { current = out }
        }
        return current
    }

    /// Dual-hue creative toning (independent highlight / shadow axes).
    private func applyCreativeToning(to image: CIImage) -> CIImage {
        let amount = CGFloat(max(0, min(1, toningAmount)))
        guard amount > 0.001 else { return image }
        let hi = CGFloat(max(-1, min(1, toningHighlights)))
        let sh = CGFloat(max(-1, min(1, toningShadows)))
        // Warm/cool on red-blue with a magenta/green cross via green channel.
        let hiR = hi * amount * 0.22
        let hiB = -hi * amount * 0.18
        let hiG = -hi * amount * 0.04
        let shR = sh * amount * 0.16
        let shB = -sh * amount * 0.22
        let shG = sh * amount * 0.05

        guard let matrix = CIFilter(name: "CIColorMatrix") else { return image }
        // Approximate split by biasing overall matrix toward highlight/shadow blend.
        let rBias = hiR * 0.65 + shR * 0.35
        let gBias = hiG * 0.55 + shG * 0.45
        let bBias = hiB * 0.55 + shB * 0.45
        matrix.setValue(image, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: 1 + rBias, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: 1 + gBias, z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 1 + bBias, w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        var current = matrix.outputImage ?? image

        // Soften highlight saturation slightly so toning reads more photographic.
        if let soft = CIFilter(name: "CIHighlightShadowAdjust") {
            soft.setValue(current, forKey: kCIInputImageKey)
            soft.setValue(NSNumber(value: 1 - 0.08 * Double(amount)), forKey: "inputHighlightAmount")
            soft.setValue(NSNumber(value: 0.04 * Double(amount)), forKey: "inputShadowAmount")
            if let out = soft.outputImage { current = out }
        }
        return current
    }

    /// Print-style matte: lifted blacks, compressed whites, muted chroma.
    private func applyMatte(to image: CIImage, amount: Double) -> CIImage {
        let s = max(0, min(1, amount))
        var current = image
        if let curve = CIFilter(name: "CIToneCurve") {
            let lift = CGFloat(s)
            curve.setValue(current, forKey: kCIInputImageKey)
            curve.setValue(CIVector(x: 0, y: 0.08 * lift), forKey: "inputPoint0")
            curve.setValue(CIVector(x: 0.2, y: 0.22 + 0.06 * lift), forKey: "inputPoint1")
            curve.setValue(CIVector(x: 0.5, y: 0.5), forKey: "inputPoint2")
            curve.setValue(CIVector(x: 0.8, y: 0.78 - 0.05 * lift), forKey: "inputPoint3")
            curve.setValue(CIVector(x: 1, y: 0.94 - 0.05 * lift), forKey: "inputPoint4")
            if let out = curve.outputImage { current = out }
        }
        if let color = CIFilter(name: "CIColorControls") {
            color.setValue(current, forKey: kCIInputImageKey)
            color.setValue(NSNumber(value: 1 - 0.28 * s), forKey: kCIInputContrastKey)
            color.setValue(NSNumber(value: max(0, 1 - 0.18 * s)), forKey: kCIInputSaturationKey)
            if let out = color.outputImage { current = out }
        }
        if let vib = CIFilter(name: "CIVibrance") {
            vib.setValue(current, forKey: kCIInputImageKey)
            vib.setValue(NSNumber(value: -0.15 * s), forKey: "inputAmount")
            if let out = vib.outputImage { current = out }
        }
        return current
    }

    /// Bright airy high-key: exposure lift, protected highlights, soft bloom.
    private func applyHighKey(to image: CIImage, amount: Double, softness: Double) -> CIImage {
        let s = max(0, min(1, amount))
        let soft = max(0, min(1, softness))
        var current = image

        if let exposure = CIFilter(name: "CIExposureAdjust") {
            exposure.setValue(current, forKey: kCIInputImageKey)
            exposure.setValue(NSNumber(value: 0.55 * s), forKey: kCIInputEVKey)
            if let out = exposure.outputImage { current = out }
        }

        if let curve = CIFilter(name: "CIToneCurve") {
            let lift = CGFloat(s)
            curve.setValue(current, forKey: kCIInputImageKey)
            curve.setValue(CIVector(x: 0, y: 0.08 * lift), forKey: "inputPoint0")
            curve.setValue(CIVector(x: 0.25, y: 0.32 + 0.08 * lift), forKey: "inputPoint1")
            curve.setValue(CIVector(x: 0.5, y: 0.58 + 0.05 * lift), forKey: "inputPoint2")
            curve.setValue(CIVector(x: 0.78, y: 0.84), forKey: "inputPoint3")
            curve.setValue(CIVector(x: 1, y: 0.97), forKey: "inputPoint4")
            if let out = curve.outputImage { current = out }
        }

        if let tonal = CIFilter(name: "CIHighlightShadowAdjust") {
            tonal.setValue(current, forKey: kCIInputImageKey)
            tonal.setValue(NSNumber(value: 1 - 0.35 * s), forKey: "inputHighlightAmount")
            tonal.setValue(NSNumber(value: 0.35 * s), forKey: "inputShadowAmount")
            if let out = tonal.outputImage { current = out }
        }

        if let color = CIFilter(name: "CIColorControls") {
            color.setValue(current, forKey: kCIInputImageKey)
            color.setValue(NSNumber(value: 0.04 * s), forKey: kCIInputBrightnessKey)
            color.setValue(NSNumber(value: 1 - 0.08 * s), forKey: kCIInputContrastKey)
            color.setValue(NSNumber(value: max(0, 1 - 0.1 * s)), forKey: kCIInputSaturationKey)
            if let out = color.outputImage { current = out }
        }

        if soft > 0.01 {
            current = applyGlow(to: current, amount: soft * s * 0.7, radius: 0.55 + soft * 0.35)
        }
        return current
    }

    /// Deep midtone contrast with controlled highlight rolloff + local clarity.
    private func applySupercontrast(to image: CIImage, amount: Double, midtones: Double) -> CIImage {
        let s = max(0, min(1, amount))
        let mid = max(0, min(1, midtones))
        var current = image

        if let curve = CIFilter(name: "CIToneCurve") {
            let punch = CGFloat(s)
            let m = CGFloat(mid)
            curve.setValue(current, forKey: kCIInputImageKey)
            curve.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
            curve.setValue(CIVector(x: 0.2, y: 0.2 - 0.1 * punch * (0.6 + 0.4 * m)), forKey: "inputPoint1")
            curve.setValue(CIVector(x: 0.5, y: 0.5 + 0.04 * punch), forKey: "inputPoint2")
            curve.setValue(CIVector(x: 0.8, y: 0.8 + 0.08 * punch * (0.5 + 0.5 * m)), forKey: "inputPoint3")
            curve.setValue(CIVector(x: 1, y: 0.985), forKey: "inputPoint4")
            if let out = curve.outputImage { current = out }
        }

        if let tonal = CIFilter(name: "CIHighlightShadowAdjust") {
            tonal.setValue(current, forKey: kCIInputImageKey)
            tonal.setValue(NSNumber(value: 1 - 0.18 * s), forKey: "inputHighlightAmount")
            tonal.setValue(NSNumber(value: -0.12 * s), forKey: "inputShadowAmount")
            if let out = tonal.outputImage { current = out }
        }

        if let local = CIFilter(name: "CIUnsharpMask") {
            local.setValue(current, forKey: kCIInputImageKey)
            local.setValue(NSNumber(value: 2.0 + 2.5 * mid), forKey: kCIInputRadiusKey)
            local.setValue(NSNumber(value: 0.18 * s * (0.45 + 0.55 * mid)), forKey: kCIInputIntensityKey)
            if let out = local.outputImage { current = out }
        }

        if let color = CIFilter(name: "CIColorControls") {
            color.setValue(current, forKey: kCIInputImageKey)
            color.setValue(NSNumber(value: 1 + 0.22 * s), forKey: kCIInputContrastKey)
            color.setValue(NSNumber(value: 1 + 0.04 * s), forKey: kCIInputSaturationKey)
            if let out = color.outputImage { current = out }
        }
        return current
    }

    /// Orton-style glow: bloom highlights, then screen-blend a soft layer.
    private func applyGlow(to image: CIImage, amount: Double, radius: Double) -> CIImage {
        let s = max(0, min(1, amount))
        let r = max(0, min(1, radius))
        guard s > 0.001 else { return image }
        let extent = image.extent

        guard let blur = CIFilter(name: "CIGaussianBlur") else { return image }
        blur.setValue(image, forKey: kCIInputImageKey)
        blur.setValue(NSNumber(value: 4 + 28 * r), forKey: kCIInputRadiusKey)
        guard var soft = blur.outputImage?.cropped(to: extent) else { return image }

        if let bloom = CIFilter(name: "CIBloom") {
            bloom.setValue(soft, forKey: kCIInputImageKey)
            bloom.setValue(NSNumber(value: 6 + 18 * r), forKey: kCIInputRadiusKey)
            bloom.setValue(NSNumber(value: 0.2 + 0.55 * s), forKey: kCIInputIntensityKey)
            if let out = bloom.outputImage?.cropped(to: extent) { soft = out }
        }

        guard let screen = CIFilter(name: "CIScreenBlendMode") else { return image }
        screen.setValue(soft, forKey: kCIInputImageKey)
        screen.setValue(image, forKey: kCIInputBackgroundImageKey)
        guard let blended = screen.outputImage?.cropped(to: extent) else { return image }

        guard let mix = CIFilter(name: "CIDissolveTransition") else { return blended }
        mix.setValue(image, forKey: kCIInputImageKey)
        mix.setValue(blended, forKey: kCIInputTargetImageKey)
        mix.setValue(NSNumber(value: 0.25 + 0.55 * s), forKey: kCIInputTimeKey)
        return mix.outputImage?.cropped(to: extent) ?? blended
    }

    /// Soft-focus: blend sharp base with gaussian blur (keeps subject readable).
    private func applySoftFocus(to image: CIImage, amount: Double) -> CIImage {
        let s = max(0, min(1, amount))
        guard s > 0.001 else { return image }
        let extent = image.extent
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return image }
        blur.setValue(image, forKey: kCIInputImageKey)
        blur.setValue(NSNumber(value: 1.5 + 10 * s), forKey: kCIInputRadiusKey)
        guard let soft = blur.outputImage?.cropped(to: extent) else { return image }

        // Screen a touch of soft layer for dreamy highlights, then dissolve back.
        var dreamy = soft
        if let screen = CIFilter(name: "CIScreenBlendMode") {
            screen.setValue(soft, forKey: kCIInputImageKey)
            screen.setValue(image, forKey: kCIInputBackgroundImageKey)
            if let out = screen.outputImage?.cropped(to: extent) { dreamy = out }
        }

        guard let mix = CIFilter(name: "CIDissolveTransition") else { return soft }
        mix.setValue(image, forKey: kCIInputImageKey)
        mix.setValue(dreamy, forKey: kCIInputTargetImageKey)
        mix.setValue(NSNumber(value: 0.2 + 0.65 * s), forKey: kCIInputTimeKey)
        return mix.outputImage?.cropped(to: extent) ?? soft
    }

    /// Luminance film grain: scaled mono noise, soft-light blend.
    private func applyFilmGrain(to image: CIImage, amount: Double, size: Double) -> CIImage {
        let s = max(0, min(1, amount))
        let sz = max(0.05, min(1, size))
        guard s > 0.001,
              var noise = CIFilter(name: "CIRandomGenerator")?.outputImage else { return image }
        let extent = image.extent

        // Larger "size" = coarser grain via downscale then upscale.
        let scale = 0.35 + 0.65 * (1 - sz)
        let scaledExtent = CGRect(
            x: extent.origin.x,
            y: extent.origin.y,
            width: max(1, extent.width * scale),
            height: max(1, extent.height * scale)
        )
        noise = noise.transformed(by: CGAffineTransform(scaleX: scale, y: scale)).cropped(to: scaledExtent)
        noise = noise.transformed(by: CGAffineTransform(scaleX: 1 / scale, y: 1 / scale)).cropped(to: extent)

        if let mono = CIFilter(name: "CIColorControls") {
            mono.setValue(noise, forKey: kCIInputImageKey)
            mono.setValue(NSNumber(value: 0), forKey: kCIInputSaturationKey)
            mono.setValue(NSNumber(value: 1.15), forKey: kCIInputContrastKey)
            if let out = mono.outputImage { noise = out.cropped(to: extent) }
        }

        if let matrix = CIFilter(name: "CIColorMatrix") {
            let grain = CGFloat(s) * 0.22
            matrix.setValue(noise, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: grain, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: grain, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: grain, w: 0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            matrix.setValue(CIVector(x: 0.5 - grain * 0.5, y: 0.5 - grain * 0.5, z: 0.5 - grain * 0.5, w: 0), forKey: "inputBiasVector")
            if let out = matrix.outputImage { noise = out.cropped(to: extent) }
        }

        guard let blend = CIFilter(name: "CISoftLightBlendMode") else { return image }
        blend.setValue(noise, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        return blend.outputImage?.cropped(to: extent) ?? image
    }


    /// Ethereal cool grade with haze bloom and soft focus.
    private func applyMystical(to image: CIImage, amount: Double, haze: Double, hue: Double) -> CIImage {
        let s = max(0, min(1, amount))
        let h = max(0, min(1, haze))
        let hueAxis = max(-1, min(1, hue))
        var current = image

        if let curve = CIFilter(name: "CIToneCurve") {
            let lift = CGFloat(s)
            curve.setValue(current, forKey: kCIInputImageKey)
            curve.setValue(CIVector(x: 0, y: 0.06 * lift), forKey: "inputPoint0")
            curve.setValue(CIVector(x: 0.25, y: 0.28 + 0.05 * lift), forKey: "inputPoint1")
            curve.setValue(CIVector(x: 0.5, y: 0.5), forKey: "inputPoint2")
            curve.setValue(CIVector(x: 0.75, y: 0.72 - 0.03 * lift), forKey: "inputPoint3")
            curve.setValue(CIVector(x: 1, y: 0.94), forKey: "inputPoint4")
            if let out = curve.outputImage { current = out }
        }

        if let color = CIFilter(name: "CIColorControls") {
            color.setValue(current, forKey: kCIInputImageKey)
            color.setValue(NSNumber(value: 1 - 0.1 * s), forKey: kCIInputContrastKey)
            color.setValue(NSNumber(value: max(0, 1 - 0.22 * s)), forKey: kCIInputSaturationKey)
            if let out = color.outputImage { current = out }
        }

        // Hue axis: negative = violet/magenta cast, positive = teal/cyan cast.
        if let matrix = CIFilter(name: "CIColorMatrix") {
            let a = CGFloat(s) * 0.2
            let violet = max(0, -hueAxis)
            let teal = max(0, hueAxis)
            matrix.setValue(current, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 1 + 0.08 * a * violet - 0.06 * a * teal, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: 1 - 0.04 * a + 0.06 * a * teal, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 1 + 0.16 * a * violet + 0.12 * a * teal, w: 0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            if let out = matrix.outputImage { current = out }
        }

        if h > 0.01 {
            current = applyGlow(to: current, amount: h * s * 0.85, radius: 0.55 + 0.35 * h)
            current = applySoftFocus(to: current, amount: h * s * 0.35)
        }

        if let temp = CIFilter(name: "CITemperatureAndTint") {
            temp.setValue(current, forKey: kCIInputImageKey)
            temp.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            temp.setValue(CIVector(x: 6500 - 520 * s, y: -40 * s + 30 * hueAxis * s), forKey: "inputTargetNeutral")
            if let out = temp.outputImage { current = out }
        }
        return current
    }

    /// Complementary warm/cool harmony with vibrance lift.
    private func applyColorHarmony(to image: CIImage, amount: Double, balance: Double) -> CIImage {
        let s = max(0, min(1, amount))
        let b = max(-1, min(1, balance))
        var current = image

        if let vib = CIFilter(name: "CIVibrance") {
            vib.setValue(current, forKey: kCIInputImageKey)
            vib.setValue(NSNumber(value: 0.35 * s), forKey: "inputAmount")
            if let out = vib.outputImage { current = out }
        }

        // Warm midtones / cool shadows when balance > 0; reverse when < 0.
        if let matrix = CIFilter(name: "CIColorMatrix") {
            let warm = CGFloat(max(0, b)) * CGFloat(s) * 0.16
            let cool = CGFloat(max(0, -b)) * CGFloat(s) * 0.16
            let mix = CGFloat(s) * 0.12
            matrix.setValue(current, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 1 + warm * 0.9 - cool * 0.35 + mix * 0.05, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: 1 + (warm - cool) * 0.15, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 1 + cool * 0.95 - warm * 0.25, w: 0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            if let out = matrix.outputImage { current = out }
        }

        if let tonal = CIFilter(name: "CIHighlightShadowAdjust") {
            tonal.setValue(current, forKey: kCIInputImageKey)
            tonal.setValue(NSNumber(value: 1 - 0.08 * s), forKey: "inputHighlightAmount")
            tonal.setValue(NSNumber(value: 0.06 * s), forKey: "inputShadowAmount")
            if let out = tonal.outputImage { current = out }
        }

        if let color = CIFilter(name: "CIColorControls") {
            color.setValue(current, forKey: kCIInputImageKey)
            color.setValue(NSNumber(value: 1 + 0.06 * s), forKey: kCIInputContrastKey)
            color.setValue(NSNumber(value: 1 + 0.08 * s), forKey: kCIInputSaturationKey)
            if let out = color.outputImage { current = out }
        }
        return current
    }

    /// Foliage greens + sky blues with gentle depth contrast (non-AI landscape polish).
    private func applyLandscape(to image: CIImage, amount: Double, foliage: Double, sky: Double) -> CIImage {
        let s = max(0, min(1, amount))
        let f = max(0, min(1, foliage))
        let skyAmt = max(0, min(1, sky))
        var current = image

        if let matrix = CIFilter(name: "CIColorMatrix") {
            let gBoost = CGFloat(s * f) * 0.18
            let bBoost = CGFloat(s * skyAmt) * 0.2
            matrix.setValue(current, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 1 - 0.04 * gBoost, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: 1 + gBoost, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 1 + bBoost - 0.03 * gBoost, w: 0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            if let out = matrix.outputImage { current = out }
        }

        if let vib = CIFilter(name: "CIVibrance") {
            vib.setValue(current, forKey: kCIInputImageKey)
            vib.setValue(NSNumber(value: 0.22 * s * (0.4 + 0.6 * max(f, skyAmt))), forKey: "inputAmount")
            if let out = vib.outputImage { current = out }
        }

        // Mild dehaze: lift local contrast and slightly deepen shadows.
        if let local = CIFilter(name: "CIUnsharpMask") {
            local.setValue(current, forKey: kCIInputImageKey)
            local.setValue(NSNumber(value: 3.5), forKey: kCIInputRadiusKey)
            local.setValue(NSNumber(value: 0.12 * s), forKey: kCIInputIntensityKey)
            if let out = local.outputImage { current = out }
        }

        if let tonal = CIFilter(name: "CIHighlightShadowAdjust") {
            tonal.setValue(current, forKey: kCIInputImageKey)
            tonal.setValue(NSNumber(value: 1 - 0.1 * s * skyAmt), forKey: "inputHighlightAmount")
            tonal.setValue(NSNumber(value: -0.08 * s), forKey: "inputShadowAmount")
            if let out = tonal.outputImage { current = out }
        }

        if let color = CIFilter(name: "CIColorControls") {
            color.setValue(current, forKey: kCIInputImageKey)
            color.setValue(NSNumber(value: 1 + 0.1 * s), forKey: kCIInputContrastKey)
            if let out = color.outputImage { current = out }
        }
        return current
    }

    /// Radial light streaks via highlight zoom-blur + warm screen blend.
    private func applySunrays(to image: CIImage, amount: Double, length: Double, warmth: Double) -> CIImage {
        let s = max(0, min(1, amount))
        let lengthAmt = max(0, min(1, length))
        let warm = max(0, min(1, warmth))
        guard s > 0.001 else { return image }
        let extent = image.extent
        let center = CIVector(
            x: extent.midX,
            y: extent.maxY - extent.height * 0.18
        )

        // Isolate bright energy for ray generation.
        var highlights = image
        if let tonal = CIFilter(name: "CIHighlightShadowAdjust") {
            tonal.setValue(image, forKey: kCIInputImageKey)
            tonal.setValue(NSNumber(value: 1.6), forKey: "inputHighlightAmount")
            tonal.setValue(NSNumber(value: -0.4), forKey: "inputShadowAmount")
            if let out = tonal.outputImage { highlights = out }
        }
        if let crush = CIFilter(name: "CIColorControls") {
            crush.setValue(highlights, forKey: kCIInputImageKey)
            crush.setValue(NSNumber(value: 1.35), forKey: kCIInputContrastKey)
            crush.setValue(NSNumber(value: -0.08), forKey: kCIInputBrightnessKey)
            if let out = crush.outputImage { highlights = out }
        }

        guard let zoom = CIFilter(name: "CIZoomBlur") else { return image }
        zoom.setValue(highlights, forKey: kCIInputImageKey)
        zoom.setValue(center, forKey: kCIInputCenterKey)
        zoom.setValue(NSNumber(value: 8 + 42 * lengthAmt), forKey: kCIInputAmountKey)
        guard var rays = zoom.outputImage?.cropped(to: extent) else { return image }

        if let warmMatrix = CIFilter(name: "CIColorMatrix") {
            let w = CGFloat(warm) * CGFloat(s) * 0.35
            warmMatrix.setValue(rays, forKey: kCIInputImageKey)
            warmMatrix.setValue(CIVector(x: 1 + 0.45 * w, y: 0, z: 0, w: 0), forKey: "inputRVector")
            warmMatrix.setValue(CIVector(x: 0, y: 1 + 0.18 * w, z: 0, w: 0), forKey: "inputGVector")
            warmMatrix.setValue(CIVector(x: 0, y: 0, z: 1 - 0.25 * w, w: 0), forKey: "inputBVector")
            warmMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            if let out = warmMatrix.outputImage { rays = out.cropped(to: extent) }
        }

        // Soft radial falloff so rays fade from the light origin.
        if let radial = CIFilter(name: "CIRadialGradient") {
            let maxR = max(extent.width, extent.height) * (0.55 + 0.55 * lengthAmt)
            radial.setValue(center, forKey: "inputCenter")
            radial.setValue(NSNumber(value: 8), forKey: "inputRadius0")
            radial.setValue(NSNumber(value: maxR), forKey: "inputRadius1")
            radial.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 1), forKey: "inputColor0")
            radial.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 0), forKey: "inputColor1")
            if let mask = radial.outputImage?.cropped(to: extent),
               let multiply = CIFilter(name: "CIMultiplyCompositing") {
                multiply.setValue(rays, forKey: kCIInputImageKey)
                multiply.setValue(mask, forKey: kCIInputBackgroundImageKey)
                if let out = multiply.outputImage?.cropped(to: extent) { rays = out }
            }
        }

        guard let screen = CIFilter(name: "CIScreenBlendMode") else { return image }
        screen.setValue(rays, forKey: kCIInputImageKey)
        screen.setValue(image, forKey: kCIInputBackgroundImageKey)
        guard let blended = screen.outputImage?.cropped(to: extent) else { return image }

        guard let mix = CIFilter(name: "CIDissolveTransition") else { return blended }
        mix.setValue(image, forKey: kCIInputImageKey)
        mix.setValue(blended, forKey: kCIInputTargetImageKey)
        mix.setValue(NSNumber(value: 0.2 + 0.7 * s), forKey: kCIInputTimeKey)
        return mix.outputImage?.cropped(to: extent) ?? blended
    }

    private func applySplitTone(to image: CIImage) -> CIImage {
        guard let matrix = CIFilter(name: "CIColorMatrix") else { return image }
        let amount = CGFloat(max(0, min(1, splitAmount))) * 0.18
        let hi = CGFloat(splitHighlight)
        let sh = CGFloat(splitShadow)
        matrix.setValue(image, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: 1 + hi * amount, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: 1 + (hi - sh) * amount * 0.35, z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 1 + sh * amount, w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        return matrix.outputImage ?? image
    }
}

/// Preview vs settled full-resolution render for the image studio surface.
enum ImageAdjustRenderQuality: Equatable {
    case preview
    case full

    var maxPixelEdge: CGFloat {
        switch self {
        case .preview: return 1600
        case .full: return 12_000
        }
    }
}
