import XCTest
@testable import LaughPlayer

final class ImageAdjustSessionTests: XCTestCase {
    func testApplyPresetUpdatesEffectiveParametersAndClearsBypass() {
        let session = ImageAdjustSession()
        session.apply(ImageAdjustParameters(exposure: 0.5, vignette: 0.4))
        session.toggleSectionBypass(.vignette)
        XCTAssertTrue(session.isSectionBypassed(.vignette))
        XCTAssertEqual(session.effectiveParameters.vignette, 0, accuracy: 0.001)

        session.apply(ImageAdjustPreset.vivid.parameters)
        XCTAssertFalse(session.isSectionBypassed(.vignette))
        XCTAssertFalse(session.effectiveParameters.isIdentity)
        XCTAssertEqual(session.rawParameters.saturation, ImageAdjustPreset.vivid.parameters.saturation, accuracy: 0.001)
    }

    func testToggleBypassOnlyWhenSectionEdited() {
        let session = ImageAdjustSession()
        session.toggleSectionBypass(.develop)
        XCTAssertFalse(session.isSectionBypassed(.develop))

        session.apply(ImageAdjustParameters(exposure: 0.3))
        session.toggleSectionBypass(.develop)
        XCTAssertTrue(session.isSectionBypassed(.develop))
        XCTAssertEqual(session.effectiveParameters.exposure, 0, accuracy: 0.001)
        XCTAssertEqual(session.rawParameters.exposure, 0.3, accuracy: 0.001)
    }

    func testResetSectionClearsBypassAndIdentityForThatTool() {
        let session = ImageAdjustSession()
        session.apply(ImageAdjustParameters(exposure: 0.4, saturation: 1.4, vignette: 0.5))
        session.toggleSectionBypass(.develop)
        session.resetSection(.develop)

        XCTAssertFalse(session.isSectionBypassed(.develop))
        XCTAssertFalse(session.isSectionEdited(.develop))
        XCTAssertTrue(session.isSectionEdited(.vignette))
        XCTAssertEqual(session.effectiveParameters.vignette, 0.5, accuracy: 0.001)
    }

    func testResetAllRestoresIdentity() {
        let session = ImageAdjustSession()
        session.apply(ImageAdjustParameters(exposure: 0.2, blackAndWhite: 1))
        session.toggleSectionBypass(.blackAndWhite)
        session.resetAll()
        XCTAssertTrue(session.effectiveParameters.isIdentity)
        XCTAssertTrue(session.rawParameters.isIdentity)
        XCTAssertFalse(session.isDirty)
    }

    func testBeforeAfterPresentationKeepsEdits() {
        let session = ImageAdjustSession()
        session.apply(ImageAdjustParameters(contrast: 1.4))
        session.setShowingBefore(true)

        XCTAssertTrue(session.isShowingBefore)
        XCTAssertTrue(session.presentationParameters.isIdentity)
        XCTAssertEqual(session.effectiveParameters.contrast, 1.4, accuracy: 0.001)
        XCTAssertEqual(session.rawParameters.contrast, 1.4, accuracy: 0.001)

        session.replaceParameters(ImageAdjustParameters(contrast: 1.6))
        XCTAssertTrue(session.presentationParameters.isIdentity)
        XCTAssertEqual(session.rawParameters.contrast, 1.6, accuracy: 0.001)

        session.setShowingBefore(false)
        XCTAssertEqual(session.presentationParameters.contrast, 1.6, accuracy: 0.001)
    }

    func testReplaceParametersEmitsPreviewThenChrome() {
        let session = ImageAdjustSession()
        var qualities: [ImageAdjustRenderQuality] = []
        var chromeCount = 0
        session.onChange = { qualities.append($0) }
        session.onChromeChange = { chromeCount += 1 }

        session.replaceParameters(ImageAdjustParameters(exposure: 0.1))
        XCTAssertEqual(qualities, [.preview])
        XCTAssertEqual(chromeCount, 1)
        XCTAssertTrue(session.isDirty)
    }

    func testApplyEmitsFullAndParametersCommitted() {
        let session = ImageAdjustSession()
        var qualities: [ImageAdjustRenderQuality] = []
        var committed = 0
        session.onChange = { qualities.append($0) }
        session.onParametersCommitted = { committed += 1 }

        session.apply(ImageAdjustParameters(hue: 0.2))
        XCTAssertEqual(qualities, [.full])
        XCTAssertEqual(committed, 1)
    }
}
