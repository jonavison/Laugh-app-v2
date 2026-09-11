import XCTest
@testable import LaughPlayer

final class EpisodeMarkerParserTests: XCTestCase {
    func testParsesSceneStyleMarkers() {
        XCTAssertEqual(
            EpisodeMarkerParser.parse(from: "Show.Name.S01E02.1080p.mkv"),
            EpisodeMarker(season: 1, episode: 2)
        )
        XCTAssertEqual(
            EpisodeMarkerParser.parse(from: "show s1e2.mp4")?.badgeText,
            "S01E02"
        )
        XCTAssertEqual(
            EpisodeMarkerParser.parse(from: "Show.S12EP104.mkv")?.badgeText,
            "S12E104"
        )
        XCTAssertEqual(
            EpisodeMarkerParser.parse(
                from: "The Lord of the Rings The Rings of Power (2022) - S01E04 - The Great Wave (1080p AMZN WEB-DL x265 Celdra).mkv"
            )?.badgeText,
            "S01E04"
        )
        XCTAssertEqual(
            EpisodeMarkerParser.parse(from: "Show.1x09.Bluray.mkv"),
            EpisodeMarker(season: 1, episode: 9)
        )
        XCTAssertEqual(
            EpisodeMarkerParser.parse(from: "Show - Season 2 Episode 11.mkv"),
            EpisodeMarker(season: 2, episode: 11)
        )
    }

    func testIgnoresNonEpisodeNames() {
        XCTAssertNil(EpisodeMarkerParser.parse(from: "Vacation Photos 2024.mov"))
        XCTAssertNil(EpisodeMarkerParser.parse(from: "Interview.mp4"))
        XCTAssertNil(EpisodeMarkerParser.parse(from: "SEcret.mkv"))
    }
}
