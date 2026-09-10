import XCTest
@testable import LaughPlayer

final class OpenSubtitlesQueryCleanerTests: XCTestCase {
    func testStripsYTSReleaseNoise() {
        let name = "Blade.Runner.2049.2017.2160p.4K.BluRay.x265.10bit.AAC5.1-[YTS.MX].mkv"
        let query = OpenSubtitlesQueryCleaner.query(fromFileName: name)
        XCTAssertEqual(query, "Blade Runner 2049")
    }

    func testKeepsSimpleTitle() {
        XCTAssertEqual(
            OpenSubtitlesQueryCleaner.query(fromFileName: "The Matrix.mp4"),
            "The Matrix"
        )
    }

    func testStripsBracketTags() {
        let name = "Dune (2021) [1080p] [BluRay].mkv"
        let query = OpenSubtitlesQueryCleaner.query(fromFileName: name)
        XCTAssertTrue(query.lowercased().contains("dune"))
        XCTAssertFalse(query.lowercased().contains("bluray"))
        XCTAssertFalse(query.contains("1080"))
    }
}

final class OpenSubtitlesConfigTests: XCTestCase {
    func testApiKeyPrefersEnvironment() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("os-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "file-key\n".write(
            to: dir.appendingPathComponent(OpenSubtitlesConfig.localKeyFileName),
            atomically: true,
            encoding: .utf8
        )
        let key = OpenSubtitlesConfig.apiKey(
            environment: [OpenSubtitlesConfig.envKeyName: " env-key "],
            packagingDirectory: dir
        )
        XCTAssertEqual(key, "env-key")
    }

    func testApiKeyFallsBackToLocalFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("os-config-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "local-key\n".write(
            to: dir.appendingPathComponent(OpenSubtitlesConfig.localKeyFileName),
            atomically: true,
            encoding: .utf8
        )
        let key = OpenSubtitlesConfig.apiKey(environment: [:], packagingDirectory: dir)
        XCTAssertEqual(key, "local-key")
    }

    func testUserAgentIncludesVersion() {
        let ua = OpenSubtitlesConfig.userAgent(version: "0.5.1")
        XCTAssertEqual(ua, "LaughPlayer v0.5.1")
    }
}

final class OpenSubtitlesClientParsingTests: XCTestCase {
    func testParseSearchFixture() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/opensubtitles-search.json")
        let data = try Data(contentsOf: url)
        let results = try OpenSubtitlesClient.parseSearchResults(data)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].fileID, 5274788)
        XCTAssertEqual(results[0].language, "en")
        XCTAssertEqual(results[0].title, "Blade Runner 2049")
        XCTAssertEqual(results[0].downloadCount, 4210)
        XCTAssertEqual(results[0].rating, 8.2)
        XCTAssertEqual(results[1].fileID, 99)
        XCTAssertEqual(results[1].language, "fr")
    }

    func testParseDownloadResponse() throws {
        let data = Data(#"{"link":"https://example.com/a.srt","file_name":"a.srt","remaining":4}"#.utf8)
        let parsed = try OpenSubtitlesClient.parseDownloadResponse(data)
        XCTAssertEqual(parsed?.link, "https://example.com/a.srt")
        XCTAssertEqual(parsed?.fileName, "a.srt")
    }

    func testClassifyQuotaStatuses() {
        XCTAssertEqual(
            OpenSubtitlesClientError.classifyHTTP(status: 406, body: nil),
            .quotaExhausted
        )
        XCTAssertEqual(
            OpenSubtitlesClientError.classifyHTTP(status: 429, body: nil),
            .quotaExhausted
        )
        XCTAssertEqual(
            OpenSubtitlesClientError.classifyHTTP(status: 403, body: "download limit exceeded"),
            .quotaExhausted
        )
    }

    func testErrorMessagesAreActionable() {
        XCTAssertTrue(OpenSubtitlesClientError.missingApiKey.userMessage.contains("Api-Key"))
        XCTAssertTrue(OpenSubtitlesClientError.quotaExhausted.userMessage.lowercased().contains("limit"))
        XCTAssertTrue(OpenSubtitlesClientError.emptyResults.userMessage.lowercased().contains("no subtitles"))
    }
}

final class OpenSubtitlesSidecarStoreTests: XCTestCase {
    func testPrefersExistingSubsFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("os-side-\(UUID().uuidString)", isDirectory: true)
        let video = root.appendingPathComponent("Movie.mkv")
        let subs = root.appendingPathComponent("Subs", isDirectory: true)
        try FileManager.default.createDirectory(at: subs, withIntermediateDirectories: true)
        try Data([0]).write(to: video)
        defer { try? FileManager.default.removeItem(at: root) }

        let dest = OpenSubtitlesSidecarStore.destinationURL(
            forVideo: video,
            language: "en",
            suggestedFileName: nil
        )
        XCTAssertEqual(dest.deletingLastPathComponent().lastPathComponent, "Subs")
        XCTAssertEqual(dest.lastPathComponent, "Movie.en.srt")
    }

    func testWriteCreatesFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("os-write-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dest = root.appendingPathComponent("a.en.srt")
        let written = try OpenSubtitlesSidecarStore.write(Data("1\n00:00:01,000 --> 00:00:02,000\nhi\n".utf8), to: dest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.path))
    }
}
