import XCTest
@testable import LaughPlayer

final class SubtitleMarkupTests: XCTestCase {
    func testStripsBalancedItalicTags() {
        let parsed = SubtitleMarkup.parse("<i>text</i> text2")
        XCTAssertEqual(parsed.text, "text text2")
        XCTAssertEqual(parsed.italicRanges, [NSRange(location: 0, length: 4)])
    }

    func testTreatsRepeatedOpenTagAsClose() {
        let parsed = SubtitleMarkup.parse("<i>text  <i> text2")
        XCTAssertEqual(parsed.text, "text text2")
        XCTAssertEqual(parsed.italicRanges, [NSRange(location: 0, length: 4)])
    }

    func testStripsTrailingItalicTagWithoutOpener() {
        XCTAssertEqual(SubtitleMarkup.parse("text  3<i>").text, "text 3")
    }

    func testUnterminatedItalicRunsToEndOfCue() {
        let parsed = SubtitleMarkup.parse("<i>whispering all the way")
        XCTAssertEqual(parsed.text, "whispering all the way")
        XCTAssertEqual(parsed.italicRanges, [NSRange(location: 0, length: 22)])
    }

    func testStripsBoldUnderlineAndFontTags() {
        let raw = "<b>Bold</b> <u>under</u> <font color=\"#00ff00\">green</font>"
        let parsed = SubtitleMarkup.parse(raw)
        XCTAssertEqual(parsed.text, "Bold under green")
        XCTAssertTrue(parsed.italicRanges.isEmpty)
    }

    func testStripsWebVTTVoiceClassAndKaraokeTags() {
        let raw = "<v Roger>Hi <c.yellow>there</c><00:00:04.500> friend"
        XCTAssertEqual(SubtitleMarkup.parse(raw).text, "Hi there friend")
    }

    func testStripsASSOverrideBlocksAndKeepsItalicRun() {
        let parsed = SubtitleMarkup.parse("{\\an8}{\\i1}slanted{\\i0} flat")
        XCTAssertEqual(parsed.text, "slanted flat")
        XCTAssertEqual(parsed.italicRanges, [NSRange(location: 0, length: 7)])
    }

    func testDecodesEntitiesAfterStrippingTags() {
        XCTAssertEqual(SubtitleMarkup.parse("Tom &amp; Jerry").text, "Tom & Jerry")
        XCTAssertEqual(SubtitleMarkup.parse("&lt;i&gt;kept&lt;/i&gt;").text, "<i>kept</i>")
        XCTAssertEqual(SubtitleMarkup.parse("caf&#233;").text, "café")
    }

    func testKeepsLiteralAngleBracketsThatAreNotTags() {
        XCTAssertEqual(SubtitleMarkup.parse("5 < 7 and x > y").text, "5 < 7 and x > y")
        XCTAssertEqual(SubtitleMarkup.parse("cost {200} credits").text, "cost {200} credits")
    }

    func testPreservesLineBreaksAndTrimsSurroundingWhitespace() {
        let parsed = SubtitleMarkup.parse("  <i>first line</i> \n <i>second line</i>  ")
        XCTAssertEqual(parsed.text, "first line\nsecond line")
        XCTAssertEqual(
            parsed.italicRanges,
            [NSRange(location: 0, length: 10), NSRange(location: 11, length: 11)]
        )
    }

    func testTagOnlyCueCollapsesToEmpty() {
        XCTAssertEqual(SubtitleMarkup.parse("<i></i>").text, "")
        XCTAssertTrue(SubtitleMarkup.parse("<i></i>").italicRanges.isEmpty)
    }

    func testPlainTextIsUnchangedWhenThereIsNoMarkup() {
        XCTAssertEqual(SubtitleMarkup.plainText("Just a normal line"), "Just a normal line")
    }
}
