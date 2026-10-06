import XCTest
@testable import LaughPlayer

final class ImageUserPresetStoreTests: XCTestCase {
    private let key = "ImageUserPresets"
    private var previousData: Data?

    override func setUp() {
        super.setUp()
        previousData = UserDefaults.standard.data(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        if let previousData {
            UserDefaults.standard.set(previousData, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testLegacyPresetJSONMigratesMissingWave2Fields() throws {
        let legacyParams = """
        {"exposure":0.4,"brightness":0,"contrast":1,"highlights":1,"shadows":0,\
        "whites":0,"blacks":0,"saturation":1,"vibrance":0,"hue":0,"temperature":0.2,\
        "tint":0,"colorBalance":0,"splitHighlight":0,"splitShadow":0,"splitAmount":0,\
        "dramatic":0,"mood":0,"matte":0,"glow":0,"glowRadius":0.45,"blur":0,\
        "filmGrain":0,"filmGrainSize":0.45,"mystical":0,"mysticalHaze":0.4,"mysticalHue":-0.25,\
        "toningAmount":0,"toningHighlights":0,"toningShadows":0,"highKey":0,"highKeySoftness":0.35,\
        "supercontrast":0,"supercontrastMidtones":0.5,"colorHarmony":0,"colorHarmonyBalance":0.15,\
        "sunrays":0,"sunraysLength":0.55,"sunraysWarmth":0.45,"landscape":0,\
        "landscapeFoliage":0.55,"landscapeSky":0.45,"blackAndWhite":0,"bwContrast":0.15,"bwWarmth":0,\
        "sharpness":0,"definition":0,"structure":0,"denoise":0,"vignette":0.3,"vignetteMidpoint":0.5,\
        "dodgeBurn":0,"dodgeBurnRange":0,"dodgeBurnSoftness":0.45}
        """
        let id = UUID()
        let payload = """
        [{"id":"\(id.uuidString)","name":"Legacy Warm","parameters":\(legacyParams)}]
        """.data(using: .utf8)!
        UserDefaults.standard.set(payload, forKey: key)

        let presets = ImageUserPresetStore.all()
        XCTAssertEqual(presets.count, 1)
        XCTAssertEqual(presets[0].name, "Legacy Warm")
        XCTAssertEqual(presets[0].parameters.exposure, 0.4, accuracy: 0.0001)
        XCTAssertEqual(presets[0].parameters.temperature, 0.2, accuracy: 0.0001)
        XCTAssertEqual(presets[0].parameters.vignette, 0.3, accuracy: 0.0001)
        XCTAssertEqual(presets[0].parameters.smartContrast, 0, accuracy: 0.0001)
        XCTAssertEqual(presets[0].parameters.curveLuma, ImageAdjustParameters.identityCurve)
        XCTAssertEqual(presets[0].parameters.distortion, 0, accuracy: 0.0001)

        // Migration should re-persist a modern payload that decodes without the fallback path.
        let modern = try XCTUnwrap(UserDefaults.standard.data(forKey: key))
        let decoded = try JSONDecoder().decode([ImageUserPreset].self, from: modern)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].parameters.exposure, 0.4, accuracy: 0.0001)
    }

    func testSaveAndReloadRoundTrip() {
        let saved = ImageUserPresetStore.save(
            name: "Wave2 Roundtrip",
            parameters: ImageAdjustParameters(smartContrast: 0.4, sharpenRadius: 0.7, distortion: -0.2)
        )
        let loaded = ImageUserPresetStore.all()
        XCTAssertTrue(loaded.contains(where: { $0.id == saved.id }))
        let match = loaded.first(where: { $0.id == saved.id })
        XCTAssertEqual(match?.parameters.smartContrast ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(match?.parameters.sharpenRadius ?? 0, 0.7, accuracy: 0.0001)
        XCTAssertEqual(match?.parameters.distortion ?? 0, -0.2, accuracy: 0.0001)
        ImageUserPresetStore.delete(id: saved.id)
    }
}
