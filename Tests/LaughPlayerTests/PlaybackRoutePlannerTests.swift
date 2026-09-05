import XCTest
@testable import LaughPlayer

final class PlaybackRoutePlannerTests: XCTestCase {
    func testMKVWithRemuxUsesAVPlayerEvenIfMpvPresent() {
        let route = PlaybackRoutePlanner.route(from: .init(
            pathExtension: "mkv",
            mpvAvailable: true,
            remuxAvailable: true,
            videoCodecTag: "h264",
            hasSidecars: false
        ))
        XCTAssertEqual(route, .compatibilityRemux(reason: "container.mkv"))
    }

    func testMKVWithoutMpvUsesRemux() {
        let route = PlaybackRoutePlanner.route(from: .init(
            pathExtension: "mkv",
            mpvAvailable: false,
            remuxAvailable: true,
            videoCodecTag: nil,
            hasSidecars: false
        ))
        XCTAssertEqual(route, .compatibilityRemux(reason: "container.mkv"))
    }

    func testMKVWithoutRemuxUsesMpv() {
        let route = PlaybackRoutePlanner.route(from: .init(
            pathExtension: "mkv",
            mpvAvailable: true,
            remuxAvailable: false,
            videoCodecTag: nil,
            hasSidecars: false
        ))
        XCTAssertEqual(route, .directMpv(reason: "container.mkv"))
    }

    func testMP4AVC1StaysNative() {
        let route = PlaybackRoutePlanner.route(from: .init(
            pathExtension: "mp4",
            mpvAvailable: true,
            remuxAvailable: true,
            videoCodecTag: "avc1",
            hasSidecars: false
        ))
        XCTAssertEqual(route, .nativeAVFoundation)
    }

    func testMP4HEV1Remuxes() {
        let route = PlaybackRoutePlanner.route(from: .init(
            pathExtension: "mp4",
            mpvAvailable: true,
            remuxAvailable: true,
            videoCodecTag: "hev1",
            hasSidecars: false
        ))
        XCTAssertEqual(route, .compatibilityRemux(reason: "codec.hev1.mp4"))
    }

    func testPrefersFastRemuxForMKVNotMP4() {
        XCTAssertTrue(PlaybackRoutePlanner.prefersFastRemux(for: URL(fileURLWithPath: "/tmp/movie.mkv")))
        XCTAssertFalse(PlaybackRoutePlanner.prefersFastRemux(for: URL(fileURLWithPath: "/tmp/movie.mp4")))
    }

    func testDirectMpvSkipsSourceDurationProbe() {
        XCTAssertFalse(PlaybackRoutePlanner.shouldProbeSourceDuration(for: .directMpv(reason: "container.mkv")))
        XCTAssertTrue(PlaybackRoutePlanner.shouldProbeSourceDuration(for: .compatibilityRemux(reason: "container.mkv")))
        XCTAssertTrue(PlaybackRoutePlanner.shouldProbeSourceDuration(for: .nativeAVFoundation))
    }
}

final class MediaKindDetectorTests: XCTestCase {
    func testReadsCommonContainers() {
        XCTAssertEqual(MediaKindDetector.kind(for: URL(fileURLWithPath: "/tmp/a.mkv")), .video)
        XCTAssertEqual(MediaKindDetector.kind(for: URL(fileURLWithPath: "/tmp/a.mp4")), .video)
        XCTAssertEqual(MediaKindDetector.kind(for: URL(fileURLWithPath: "/tmp/a.png")), .image)
        XCTAssertEqual(MediaKindDetector.kind(for: URL(fileURLWithPath: "/tmp/a.jpg")), .image)
        XCTAssertEqual(MediaKindDetector.kind(for: URL(fileURLWithPath: "/tmp/a.txt")), .unsupported)
    }
}
