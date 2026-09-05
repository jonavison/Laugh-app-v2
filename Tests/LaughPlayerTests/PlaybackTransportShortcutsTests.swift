import AppKit
import XCTest
@testable import LaughPlayer

final class PlaybackTransportShortcutsTests: XCTestCase {
    func testChordModifiersIgnoreNumericPadAndFunctionFlags() {
        let arrowFlags: NSEvent.ModifierFlags = [.numericPad, .function]
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: arrowFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 126
        )!
        XCTAssertTrue(PlaybackTransportShortcuts.chordModifiers(from: event).isEmpty)

        let optionArrow = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: arrowFlags.union(.option),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 124
        )!
        XCTAssertEqual(PlaybackTransportShortcuts.chordModifiers(from: optionArrow), .option)
    }

    func testTextEditingBlocksTransportShortcuts() {
        let field = NSTextField(string: "hi")
        field.isEditable = true
        XCTAssertTrue(PlaybackTransportShortcuts.blocksTransportShortcuts(firstResponder: field))

        let label = NSTextField(labelWithString: "hi")
        XCTAssertFalse(PlaybackTransportShortcuts.blocksTransportShortcuts(firstResponder: label))

        let slider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
        XCTAssertFalse(PlaybackTransportShortcuts.blocksTransportShortcuts(firstResponder: slider))
    }

    func testVerticalScrollMapsToVolumeSteps() {
        var volumeAcc: CGFloat = 0
        var seekAcc: CGFloat = 0
        let action = PlaybackTransportShortcuts.consumeScroll(
            deltaX: 0,
            deltaY: 1,
            shiftPressed: false,
            hasPreciseDeltas: false,
            volumeAccumulator: &volumeAcc,
            seekAccumulator: &seekAcc
        )
        XCTAssertEqual(action, .volume(PlaybackTransportShortcuts.volumeStep))
    }

    func testHorizontalScrollMapsToSeek() {
        var volumeAcc: CGFloat = 0
        var seekAcc: CGFloat = 0
        let action = PlaybackTransportShortcuts.consumeScroll(
            deltaX: 1,
            deltaY: 0,
            shiftPressed: false,
            hasPreciseDeltas: false,
            volumeAccumulator: &volumeAcc,
            seekAccumulator: &seekAcc
        )
        XCTAssertEqual(action, .seek(PlaybackTransportShortcuts.standardSeekSeconds))
    }

    func testShiftVerticalScrollMapsToSeek() {
        var volumeAcc: CGFloat = 0
        var seekAcc: CGFloat = 0
        let action = PlaybackTransportShortcuts.consumeScroll(
            deltaX: 0,
            deltaY: -1,
            shiftPressed: true,
            hasPreciseDeltas: false,
            volumeAccumulator: &volumeAcc,
            seekAccumulator: &seekAcc
        )
        XCTAssertEqual(action, .seek(-PlaybackTransportShortcuts.standardSeekSeconds))
    }

    func testPreciseVerticalScrollMapsContinuouslyToVolume() {
        var volumeAcc: CGFloat = 0
        var seekAcc: CGFloat = 0
        let action = PlaybackTransportShortcuts.consumeScroll(
            deltaX: 0,
            deltaY: 2,
            shiftPressed: false,
            hasPreciseDeltas: true,
            volumeAccumulator: &volumeAcc,
            seekAccumulator: &seekAcc
        )
        XCTAssertEqual(action, .volume(Float(2) * 0.025))
    }

    func testSmallHorizontalJitterDoesNotStealVolumeScroll() {
        var volumeAcc: CGFloat = 0
        var seekAcc: CGFloat = 0
        let action = PlaybackTransportShortcuts.consumeScroll(
            deltaX: 0.2,
            deltaY: 1,
            shiftPressed: false,
            hasPreciseDeltas: false,
            volumeAccumulator: &volumeAcc,
            seekAccumulator: &seekAcc
        )
        XCTAssertEqual(action, .volume(PlaybackTransportShortcuts.volumeStep))
    }
}
