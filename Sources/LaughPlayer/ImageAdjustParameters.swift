import CoreImage
import Foundation

/// Expandable Edits tools that own a subset of `ImageAdjustParameters`.
enum ImageAdjustSection: String, CaseIterable, Hashable {
    case develop
    case color
    case curves
    case hsl
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
    case optics

    var title: String {
        switch self {
        case .develop: return "Develop"
        case .color: return "Color"
        case .curves: return "Curves"
        case .hsl: return "HSL"
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
        case .denoise: return "Noise Reduction"
        case .dodgeBurn: return "Dodge & Burn"
        case .vignette: return "Vignette"
        case .optics: return "Optics"
        }
    }
}

/// Shared display-only develop parameters for **ImageMedia** (see ADR 0004).
struct ImageAdjustParameters: Equatable, Codable {
    // Light
    var exposure: Double
    var brightness: Double
    var contrast: Double
    var smartContrast: Double
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

    // Curves — five Y values at X = 0, 0.25, 0.5, 0.75, 1 (identity diagonal)
    var curveLuma: [Double]
    var curveRed: [Double]
    var curveGreen: [Double]
    var curveBlue: [Double]

    // HSL — 8 channels (R O Y G A B P M): hue / sat / luma offsets
    var hslHue: [Double]
    var hslSat: [Double]
    var hslLuma: [Double]

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
    var sharpenRadius: Double
    var sharpenDetail: Double
    var definition: Double
    var structure: Double
    var denoise: Double
    var denoiseColor: Double
    var denoiseDetail: Double

    // Effects
    var vignette: Double
    var vignetteMidpoint: Double
    var vignetteCenterX: Double
    var vignetteCenterY: Double
    var dodgeBurn: Double
    var dodgeBurnRange: Double
    var dodgeBurnSoftness: Double

    // Optics (manual)
    var distortion: Double
    var chromaticAberration: Double
    var defringePurple: Double
    var defringeGreen: Double

    static let identityCurve: [Double] = [0, 0.25, 0.5, 0.75, 1]
    static let hslChannelCount = 8

    init(
        exposure: Double = 0,
        brightness: Double = 0,
        contrast: Double = 1,
        smartContrast: Double = 0,
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
        curveLuma: [Double] = ImageAdjustParameters.identityCurve,
        curveRed: [Double] = ImageAdjustParameters.identityCurve,
        curveGreen: [Double] = ImageAdjustParameters.identityCurve,
        curveBlue: [Double] = ImageAdjustParameters.identityCurve,
        hslHue: [Double] = Array(repeating: 0, count: ImageAdjustParameters.hslChannelCount),
        hslSat: [Double] = Array(repeating: 0, count: ImageAdjustParameters.hslChannelCount),
        hslLuma: [Double] = Array(repeating: 0, count: ImageAdjustParameters.hslChannelCount),
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
        sharpenRadius: Double = 0.4,
        sharpenDetail: Double = 0.5,
        definition: Double = 0,
        structure: Double = 0,
        denoise: Double = 0,
        denoiseColor: Double = 0,
        denoiseDetail: Double = 0.5,
        vignette: Double = 0,
        vignetteMidpoint: Double = 0.5,
        vignetteCenterX: Double = 0.5,
        vignetteCenterY: Double = 0.5,
        dodgeBurn: Double = 0,
        dodgeBurnRange: Double = 0,
        dodgeBurnSoftness: Double = 0.45,
        distortion: Double = 0,
        chromaticAberration: Double = 0,
        defringePurple: Double = 0,
        defringeGreen: Double = 0
    ) {
        self.exposure = exposure
        self.brightness = brightness
        self.contrast = contrast
        self.smartContrast = smartContrast
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
        self.curveLuma = Self.normalizedCurve(curveLuma)
        self.curveRed = Self.normalizedCurve(curveRed)
        self.curveGreen = Self.normalizedCurve(curveGreen)
        self.curveBlue = Self.normalizedCurve(curveBlue)
        self.hslHue = Self.normalizedHSL(hslHue)
        self.hslSat = Self.normalizedHSL(hslSat)
        self.hslLuma = Self.normalizedHSL(hslLuma)
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
        self.sharpenRadius = sharpenRadius
        self.sharpenDetail = sharpenDetail
        self.definition = definition
        self.structure = structure
        self.denoise = denoise
        self.denoiseColor = denoiseColor
        self.denoiseDetail = denoiseDetail
        self.vignette = vignette
        self.vignetteMidpoint = vignetteMidpoint
        self.vignetteCenterX = vignetteCenterX
        self.vignetteCenterY = vignetteCenterY
        self.dodgeBurn = dodgeBurn
        self.dodgeBurnRange = dodgeBurnRange
        self.dodgeBurnSoftness = dodgeBurnSoftness
        self.distortion = distortion
        self.chromaticAberration = chromaticAberration
        self.defringePurple = defringePurple
        self.defringeGreen = defringeGreen
    }

    private static func normalizedCurve(_ values: [Double]) -> [Double] {
        var out = values
        while out.count < 5 { out.append(identityCurve[out.count]) }
        if out.count > 5 { out = Array(out.prefix(5)) }
        out[0] = max(0, min(1, out[0]))
        out[4] = max(0, min(1, out[4]))
        for i in 1..<4 { out[i] = max(0, min(1, out[i])) }
        return out
    }

    private static func normalizedHSL(_ values: [Double]) -> [Double] {
        var out = values
        while out.count < hslChannelCount { out.append(0) }
        if out.count > hslChannelCount { out = Array(out.prefix(hslChannelCount)) }
        return out.map { max(-1, min(1, $0)) }
    }

    static let identity = ImageAdjustParameters()

    /// Blend two looks. `amount` 0 = `from` (dry), 1 = `to` (wet). Numeric fields lerp; other JSON values snap at 0.5.
    static func mixed(from dry: ImageAdjustParameters, to wet: ImageAdjustParameters, amount: Double) -> ImageAdjustParameters {
        let t = min(1, max(0, amount))
        if t <= 0 { return dry }
        if t >= 1 { return wet }
        do {
            let encoder = JSONEncoder()
            let dryData = try encoder.encode(dry)
            let wetData = try encoder.encode(wet)
            let dryObject = try JSONSerialization.jsonObject(with: dryData)
            let wetObject = try JSONSerialization.jsonObject(with: wetData)
            let blended = mixedJSONValue(dryObject, wetObject, amount: t)
            let data = try JSONSerialization.data(withJSONObject: blended)
            return try JSONDecoder().decode(ImageAdjustParameters.self, from: data)
        } catch {
            return t < 0.5 ? dry : wet
        }
    }

    private static func mixedJSONValue(_ a: Any, _ b: Any, amount t: Double) -> Any {
        if let ad = jsonDouble(a), let bd = jsonDouble(b) {
            return ad + (bd - ad) * t
        }
        if let aa = a as? [Any], let ba = b as? [Any] {
            let count = max(aa.count, ba.count)
            return (0..<count).map { index in
                let av = index < aa.count ? aa[index] : ba[index]
                let bv = index < ba.count ? ba[index] : aa[index]
                return mixedJSONValue(av, bv, amount: t)
            }
        }
        if let ad = a as? [String: Any], let bd = b as? [String: Any] {
            var out: [String: Any] = [:]
            for key in Set(ad.keys).union(bd.keys) {
                if let av = ad[key], let bv = bd[key] {
                    out[key] = mixedJSONValue(av, bv, amount: t)
                } else if t < 0.5, let av = ad[key] {
                    out[key] = av
                } else if let bv = bd[key] {
                    out[key] = bv
                }
            }
            return out
        }
        return t < 0.5 ? a : b
    }

    private static func jsonDouble(_ value: Any) -> Double? {
        if let n = value as? NSNumber {
            let objCType = String(cString: n.objCType)
            // Skip Bool. NSNumber 0/1 also bridge to Bool — check objCType first.
            if objCType == "c" || objCType == "B" { return nil }
            return n.doubleValue
        }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    /// Decode params that may predate newer fields by filling gaps from identity.
    static func decodingLenient(from data: Data) throws -> ImageAdjustParameters {
        let identityData = try JSONEncoder().encode(identity)
        guard var base = try JSONSerialization.jsonObject(with: identityData) as? [String: Any],
              let incoming = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return try JSONDecoder().decode(ImageAdjustParameters.self, from: data)
        }
        for (key, value) in incoming {
            base[key] = value
        }
        let merged = try JSONSerialization.data(withJSONObject: base)
        return try JSONDecoder().decode(ImageAdjustParameters.self, from: merged)
    }

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
                || !near(smartContrast, id.smartContrast)
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
        case .curves:
            return !nearCurve(curveLuma, id.curveLuma)
                || !nearCurve(curveRed, id.curveRed)
                || !nearCurve(curveGreen, id.curveGreen)
                || !nearCurve(curveBlue, id.curveBlue)
        case .hsl:
            return !nearHSL(hslHue, id.hslHue)
                || !nearHSL(hslSat, id.hslSat)
                || !nearHSL(hslLuma, id.hslLuma)
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
                || !near(sharpenRadius, id.sharpenRadius)
                || !near(sharpenDetail, id.sharpenDetail)
                || !near(definition, id.definition)
                || !near(structure, id.structure)
        case .denoise:
            return !near(denoise, id.denoise)
                || !near(denoiseColor, id.denoiseColor)
                || !near(denoiseDetail, id.denoiseDetail)
        case .vignette:
            return !near(vignette, id.vignette)
                || !near(vignetteMidpoint, id.vignetteMidpoint)
                || !near(vignetteCenterX, id.vignetteCenterX)
                || !near(vignetteCenterY, id.vignetteCenterY)
        case .dodgeBurn:
            return !near(dodgeBurn, id.dodgeBurn)
                || !near(dodgeBurnRange, id.dodgeBurnRange)
                || !near(dodgeBurnSoftness, id.dodgeBurnSoftness)
        case .optics:
            return !near(distortion, id.distortion)
                || !near(chromaticAberration, id.chromaticAberration)
                || !near(defringePurple, id.defringePurple)
                || !near(defringeGreen, id.defringeGreen)
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
            next.smartContrast = id.smartContrast
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
        case .curves:
            next.curveLuma = id.curveLuma
            next.curveRed = id.curveRed
            next.curveGreen = id.curveGreen
            next.curveBlue = id.curveBlue
        case .hsl:
            next.hslHue = id.hslHue
            next.hslSat = id.hslSat
            next.hslLuma = id.hslLuma
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
            next.sharpenRadius = id.sharpenRadius
            next.sharpenDetail = id.sharpenDetail
            next.definition = id.definition
            next.structure = id.structure
        case .denoise:
            next.denoise = id.denoise
            next.denoiseColor = id.denoiseColor
            next.denoiseDetail = id.denoiseDetail
        case .vignette:
            next.vignette = id.vignette
            next.vignetteMidpoint = id.vignetteMidpoint
            next.vignetteCenterX = id.vignetteCenterX
            next.vignetteCenterY = id.vignetteCenterY
        case .dodgeBurn:
            next.dodgeBurn = id.dodgeBurn
            next.dodgeBurnRange = id.dodgeBurnRange
            next.dodgeBurnSoftness = id.dodgeBurnSoftness
        case .optics:
            next.distortion = id.distortion
            next.chromaticAberration = id.chromaticAberration
            next.defringePurple = id.defringePurple
            next.defringeGreen = id.defringeGreen
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

    private func nearCurve(_ a: [Double], _ b: [Double]) -> Bool {
        zip(Self.normalizedCurve(a), Self.normalizedCurve(b)).allSatisfy { near($0, $1) }
    }

    private func nearHSL(_ a: [Double], _ b: [Double]) -> Bool {
        zip(Self.normalizedHSL(a), Self.normalizedHSL(b)).allSatisfy { near($0, $1) }
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

        if smartContrast > 0.001 {
            current = applySmartContrast(to: current, amount: smartContrast)
        }

        if isCurveEdited(curveLuma) || isCurveEdited(curveRed) || isCurveEdited(curveGreen) || isCurveEdited(curveBlue) {
            current = applyToneCurves(to: current)
        }

        if isHSLEdited {
            current = applyHSL(to: current)
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
            // Sliders are creative / Lightroom-style: +temp warms, +tint magentas.
            // CITemperatureAndTint vectors are illuminant-style (higher K = cooler;
            // +Y tint = greener), so invert when driving targetNeutral.
            let neutral = CIVector(x: 6500, y: 0)
            let target = CIVector(
                x: 6500 - CGFloat(temperature) * 4200,
                y: CGFloat(-tint) * 160
            )
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

        if denoise > 0.001 || denoiseColor > 0.001 {
            current = applyNoiseReduction(to: current)
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

        if sharpness > 0.001 {
            current = applySharpening(to: current)
        }

        if abs(distortion) >= 0.001 || chromaticAberration > 0.001
            || defringePurple > 0.001 || defringeGreen > 0.001 {
            current = applyOptics(to: current)
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

        if vignette > 0.001 {
            current = applyVignette(to: current)
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

    // MARK: - Pro Wave 2 / Optics helpers

    private func isCurveEdited(_ curve: [Double]) -> Bool {
        !nearCurve(curve, Self.identityCurve)
    }

    private var isHSLEdited: Bool {
        !nearHSL(hslHue, Array(repeating: 0, count: Self.hslChannelCount))
            || !nearHSL(hslSat, Array(repeating: 0, count: Self.hslChannelCount))
            || !nearHSL(hslLuma, Array(repeating: 0, count: Self.hslChannelCount))
    }

    private func applySmartContrast(to image: CIImage, amount: Double) -> CIImage {
        let s = max(0, min(1, amount))
        guard s > 0.001, let filter = CIFilter(name: "CIToneCurve") else { return image }
        // Midtone S-curve — stronger lift in mids without clipping ends hard.
        let pull = CGFloat(s * 0.14)
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
        filter.setValue(CIVector(x: 0.25, y: 0.25 - pull * 0.55), forKey: "inputPoint1")
        filter.setValue(CIVector(x: 0.5, y: 0.5), forKey: "inputPoint2")
        filter.setValue(CIVector(x: 0.75, y: 0.75 + pull * 0.55), forKey: "inputPoint3")
        filter.setValue(CIVector(x: 1, y: 1), forKey: "inputPoint4")
        return filter.outputImage ?? image
    }

    private func applyToneCurves(to image: CIImage) -> CIImage {
        var current = image
        if isCurveEdited(curveLuma), let filter = CIFilter(name: "CIToneCurve") {
            applyCurvePoints(curveLuma, to: filter, image: current)
            if let out = filter.outputImage { current = out }
        }
        // Per-channel via color matrix mixes after RGB curves approximated with tone curve on separated channels.
        if isCurveEdited(curveRed) || isCurveEdited(curveGreen) || isCurveEdited(curveBlue) {
            current = applyRGBCurves(to: current)
        }
        return current
    }

    private func applyCurvePoints(_ curve: [Double], to filter: CIFilter, image: CIImage) {
        let c = Self.normalizedCurve(curve)
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 0, y: CGFloat(c[0])), forKey: "inputPoint0")
        filter.setValue(CIVector(x: 0.25, y: CGFloat(c[1])), forKey: "inputPoint1")
        filter.setValue(CIVector(x: 0.5, y: CGFloat(c[2])), forKey: "inputPoint2")
        filter.setValue(CIVector(x: 0.75, y: CGFloat(c[3])), forKey: "inputPoint3")
        filter.setValue(CIVector(x: 1, y: CGFloat(c[4])), forKey: "inputPoint4")
    }

    private func applyRGBCurves(to image: CIImage) -> CIImage {
        let extent = image.extent
        func curvedChannel(_ curve: [Double], sourceWeights: (CGFloat, CGFloat, CGFloat)) -> CIImage? {
            // Lift the source channel into grayscale so CIToneCurve remaps that channel's values.
            guard let toGray = CIFilter(name: "CIColorMatrix") else { return nil }
            let (wr, wg, wb) = sourceWeights
            toGray.setValue(image, forKey: kCIInputImageKey)
            toGray.setValue(CIVector(x: wr, y: wg, z: wb, w: 0), forKey: "inputRVector")
            toGray.setValue(CIVector(x: wr, y: wg, z: wb, w: 0), forKey: "inputGVector")
            toGray.setValue(CIVector(x: wr, y: wg, z: wb, w: 0), forKey: "inputBVector")
            toGray.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            guard var gray = toGray.outputImage else { return nil }
            if isCurveEdited(curve), let tone = CIFilter(name: "CIToneCurve") {
                applyCurvePoints(curve, to: tone, image: gray)
                gray = tone.outputImage ?? gray
            }
            return gray.cropped(to: extent)
        }

        func keepChannel(_ gray: CIImage, channel: OpticsChannel) -> CIImage? {
            guard let matrix = CIFilter(name: "CIColorMatrix") else { return nil }
            matrix.setValue(gray, forKey: kCIInputImageKey)
            switch channel {
            case .red:
                matrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
                matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
            case .green:
                matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
                matrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputGVector")
                matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
            case .blue:
                matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
                matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
                matrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputBVector")
            }
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            return matrix.outputImage?.cropped(to: extent)
        }

        guard let rGray = curvedChannel(curveRed, sourceWeights: (1, 0, 0)),
              let gGray = curvedChannel(curveGreen, sourceWeights: (0, 1, 0)),
              let bGray = curvedChannel(curveBlue, sourceWeights: (0, 0, 1)),
              let r = keepChannel(rGray, channel: .red),
              let g = keepChannel(gGray, channel: .green),
              let b = keepChannel(bGray, channel: .blue),
              let add1 = CIFilter(name: "CIAdditionCompositing"),
              let add2 = CIFilter(name: "CIAdditionCompositing")
        else { return image }

        add1.setValue(r, forKey: kCIInputImageKey)
        add1.setValue(g, forKey: kCIInputBackgroundImageKey)
        guard let rg = add1.outputImage else { return image }
        add2.setValue(rg, forKey: kCIInputImageKey)
        add2.setValue(b, forKey: kCIInputBackgroundImageKey)
        return add2.outputImage?.cropped(to: extent) ?? image
    }

    private func applyHSL(to image: CIImage) -> CIImage {
        guard isHSLEdited else { return image }
        let dimension = 16
        let count = dimension * dimension * dimension
        var cube = [Float](repeating: 0, count: count * 4)
        // Channel centers in degrees: R O Y G A B P M
        let centers: [Double] = [0, 30, 60, 120, 180, 240, 275, 315]
        let halfWidth = 28.0

        for b in 0..<dimension {
            for g in 0..<dimension {
                for r in 0..<dimension {
                    let rf = Double(r) / Double(dimension - 1)
                    let gf = Double(g) / Double(dimension - 1)
                    let bf = Double(b) / Double(dimension - 1)
                    var (h, s, l) = rgbToHSL(rf, gf, bf)

                    for i in 0..<Self.hslChannelCount {
                        let hueEdit = hslHue[i]
                        let satEdit = hslSat[i]
                        let lumaEdit = hslLuma[i]
                        if abs(hueEdit) < 0.001, abs(satEdit) < 0.001, abs(lumaEdit) < 0.001 {
                            continue
                        }
                        let weight = hueWeight(h, center: centers[i], halfWidth: halfWidth)
                        guard weight > 0.001 else { continue }
                        h = (h + hueEdit * 40 * weight + 360).truncatingRemainder(dividingBy: 360)
                        s = max(0, min(1, s + satEdit * 0.55 * weight))
                        l = max(0, min(1, l + lumaEdit * 0.22 * weight))
                    }

                    let (or, og, ob) = hslToRGB(h, s, l)
                    let idx = (b * dimension * dimension + g * dimension + r) * 4
                    cube[idx] = Float(or)
                    cube[idx + 1] = Float(og)
                    cube[idx + 2] = Float(ob)
                    cube[idx + 3] = 1
                }
            }
        }

        guard let filter = CIFilter(name: "CIColorCube") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(dimension, forKey: "inputCubeDimension")
        let data = cube.withUnsafeBufferPointer { Data(buffer: $0) }
        filter.setValue(data, forKey: "inputCubeData")
        return filter.outputImage?.cropped(to: image.extent) ?? image
    }

    private func hueWeight(_ hue: Double, center: Double, halfWidth: Double) -> Double {
        var d = abs(hue - center)
        if d > 180 { d = 360 - d }
        if d >= halfWidth { return 0 }
        let t = 1 - d / halfWidth
        return t * t * (3 - 2 * t)
    }

    private func rgbToHSL(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxC = max(r, max(g, b))
        let minC = min(r, min(g, b))
        let l = (maxC + minC) / 2
        let delta = maxC - minC
        guard delta > 1e-6 else { return (0, 0, l) }
        let s = l > 0.5 ? delta / (2 - maxC - minC) : delta / (maxC + minC)
        var h: Double
        if maxC == r {
            h = (g - b) / delta + (g < b ? 6 : 0)
        } else if maxC == g {
            h = (b - r) / delta + 2
        } else {
            h = (r - g) / delta + 4
        }
        h *= 60
        return (h, s, l)
    }

    private func hslToRGB(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        guard s > 1e-6 else { return (l, l, l) }
        func hue2rgb(_ p: Double, _ q: Double, _ tIn: Double) -> Double {
            var t = tIn
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        let hk = h / 360
        return (hue2rgb(p, q, hk + 1 / 3), hue2rgb(p, q, hk), hue2rgb(p, q, hk - 1 / 3))
    }

    private func applySharpening(to image: CIImage) -> CIImage {
        let amount = max(0, sharpness)
        let radius = 0.4 + max(0, min(1, sharpenRadius)) * 3.6
        let detail = max(0, min(1, sharpenDetail))
        guard let unsharp = CIFilter(name: "CIUnsharpMask") else { return image }
        unsharp.setValue(image, forKey: kCIInputImageKey)
        unsharp.setValue(NSNumber(value: radius), forKey: kCIInputRadiusKey)
        unsharp.setValue(NSNumber(value: amount * (0.35 + detail * 0.55)), forKey: kCIInputIntensityKey)
        guard let sharp = unsharp.outputImage else { return image }
        // Low detail → blend toward edge-only (mix original back into flats).
        let edgeBias = 1 - detail
        guard edgeBias > 0.05, let mix = CIFilter(name: "CIDissolveTransition") else { return sharp }
        mix.setValue(sharp, forKey: kCIInputImageKey)
        mix.setValue(image, forKey: kCIInputTargetImageKey)
        mix.setValue(NSNumber(value: edgeBias * 0.45), forKey: kCIInputTimeKey)
        return mix.outputImage?.cropped(to: image.extent) ?? sharp
    }

    private func applyNoiseReduction(to image: CIImage) -> CIImage {
        var current = image
        let luma = max(0, min(1, denoise))
        let color = max(0, min(1, denoiseColor))
        let detailKeep = max(0, min(1, denoiseDetail))
        if luma > 0.001, let filter = CIFilter(name: "CINoiseReduction") {
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(NSNumber(value: luma * 0.08 * (1.15 - detailKeep * 0.45)), forKey: "inputNoiseLevel")
            filter.setValue(NSNumber(value: 0.25 + detailKeep * 0.55), forKey: "inputSharpness")
            if let out = filter.outputImage { current = out }
        }
        if color > 0.001, let blur = CIFilter(name: "CIGaussianBlur") {
            // Soft chroma smooth: blur then mix luma back from original.
            blur.setValue(current, forKey: kCIInputImageKey)
            blur.setValue(NSNumber(value: 0.6 + color * 2.2), forKey: kCIInputRadiusKey)
            if let soft = blur.outputImage?.cropped(to: current.extent),
               let mix = CIFilter(name: "CIDissolveTransition") {
                mix.setValue(current, forKey: kCIInputImageKey)
                mix.setValue(soft, forKey: kCIInputTargetImageKey)
                mix.setValue(NSNumber(value: color * 0.55 * (1 - detailKeep * 0.35)), forKey: kCIInputTimeKey)
                if let out = mix.outputImage?.cropped(to: current.extent) { current = out }
            }
        }
        return current
    }

    private func applyVignette(to image: CIImage) -> CIImage {
        let mid = max(0, min(1, vignetteMidpoint))
        let cx = max(0, min(1, vignetteCenterX))
        let cy = max(0, min(1, vignetteCenterY))
        let extent = image.extent
        let center = CGPoint(
            x: extent.midX - (0.5 - cx) * extent.width,
            y: extent.midY - (0.5 - cy) * extent.height
        )
        if abs(cx - 0.5) < 0.01, abs(cy - 0.5) < 0.01, let filter = CIFilter(name: "CIVignette") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(NSNumber(value: vignette * 1.35), forKey: kCIInputIntensityKey)
            filter.setValue(NSNumber(value: 0.55 + mid * 1.55 + vignette * 0.25), forKey: kCIInputRadiusKey)
            return filter.outputImage ?? image
        }
        if let filter = CIFilter(name: "CIVignetteEffect") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(CIVector(x: center.x, y: center.y), forKey: kCIInputCenterKey)
            filter.setValue(NSNumber(value: vignette * 1.2), forKey: kCIInputIntensityKey)
            let radius = min(extent.width, extent.height) * (0.35 + mid * 0.55)
            filter.setValue(NSNumber(value: radius), forKey: kCIInputRadiusKey)
            return filter.outputImage?.cropped(to: extent) ?? image
        }
        return image
    }

    private func applyOptics(to image: CIImage) -> CIImage {
        var current = image
        let extent = image.extent
        if abs(distortion) >= 0.001, let bump = CIFilter(name: "CIBumpDistortion") {
            let scale = CGFloat(-distortion * 0.35)
            bump.setValue(current, forKey: kCIInputImageKey)
            bump.setValue(CIVector(x: extent.midX, y: extent.midY), forKey: kCIInputCenterKey)
            bump.setValue(NSNumber(value: min(extent.width, extent.height) * 0.55), forKey: kCIInputRadiusKey)
            bump.setValue(NSNumber(value: scale), forKey: kCIInputScaleKey)
            if let out = bump.outputImage?.cropped(to: extent) { current = out }
        }
        if chromaticAberration > 0.001 {
            let shift = chromaticAberration * 1.8
            if let r = shiftedChannel(current, dx: shift, dy: 0, keep: .red),
               let b = shiftedChannel(current, dx: -shift, dy: 0, keep: .blue),
               let g = shiftedChannel(current, dx: 0, dy: 0, keep: .green),
               let add1 = CIFilter(name: "CIAdditionCompositing"),
               let add2 = CIFilter(name: "CIAdditionCompositing") {
                add1.setValue(r, forKey: kCIInputImageKey)
                add1.setValue(g, forKey: kCIInputBackgroundImageKey)
                if let rg = add1.outputImage {
                    add2.setValue(rg, forKey: kCIInputImageKey)
                    add2.setValue(b, forKey: kCIInputBackgroundImageKey)
                    if let out = add2.outputImage?.cropped(to: extent) { current = out }
                }
            }
        }
        if defringePurple > 0.001 || defringeGreen > 0.001,
           let controls = CIFilter(name: "CIColorControls") {
            let amount = max(defringePurple, defringeGreen) * 0.35
            controls.setValue(current, forKey: kCIInputImageKey)
            controls.setValue(NSNumber(value: 1 - amount), forKey: kCIInputSaturationKey)
            controls.setValue(NSNumber(value: 0), forKey: kCIInputBrightnessKey)
            controls.setValue(NSNumber(value: 1), forKey: kCIInputContrastKey)
            if let desat = controls.outputImage,
               let edges = CIFilter(name: "CIEdges") {
                edges.setValue(current, forKey: kCIInputImageKey)
                edges.setValue(NSNumber(value: 2.5), forKey: kCIInputIntensityKey)
                if let edgeMask = edges.outputImage,
                   let mix = CIFilter(name: "CIBlendWithMask") {
                    mix.setValue(desat, forKey: kCIInputImageKey)
                    mix.setValue(current, forKey: kCIInputBackgroundImageKey)
                    mix.setValue(edgeMask, forKey: kCIInputMaskImageKey)
                    if let out = mix.outputImage?.cropped(to: extent) { current = out }
                }
            }
        }
        return current
    }

    private enum OpticsChannel { case red, green, blue }

    private func shiftedChannel(_ image: CIImage, dx: Double, dy: Double, keep: OpticsChannel) -> CIImage? {
        let extent = image.extent
        var src = image
        if abs(dx) > 0.001 || abs(dy) > 0.001 {
            let t = CGAffineTransform(translationX: CGFloat(dx), y: CGFloat(dy))
            src = image.transformed(by: t).cropped(to: extent)
        }
        guard let matrix = CIFilter(name: "CIColorMatrix") else { return nil }
        matrix.setValue(src, forKey: kCIInputImageKey)
        switch keep {
        case .red:
            matrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        case .green:
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        case .blue:
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        }
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        return matrix.outputImage?.cropped(to: extent)
    }

    /// Solve Temperature / Tint (−1…1) so a sampled near-neutral becomes grey under `CITemperatureAndTint`.
    static func whiteBalanceOffsets(fromNeutralRGB r: Double, g: Double, b: Double) -> (temperature: Double, tint: Double) {
        let avg = max((r + g + b) / 3.0, 1e-4)
        // Warm cast → cool correction (negative temperature / left / blue).
        let temperature = max(-1, min(1, (b - r) / avg * 0.95))
        // Green cast → magenta correction (positive tint / right / magenta).
        let tint = max(-1, min(1, (g - (r + b) * 0.5) / avg * 0.95))
        return (temperature, tint)
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
