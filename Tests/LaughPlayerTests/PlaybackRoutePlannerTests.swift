import XCTest
@testable import LaughPlayer

final class PlaybackRoutePlannerTests: XCTestCase {
    func testMKVWithRemuxUsesAVPlayerEvenIfMpvPresent() {
        let route = PlaybackRoutePlanner.route(from: .init(
            pathExtension: "mkv",
            mpvAvailable: true,
            remuxAvailable: true,
            videoCodecTag: "h264",
            hasSidecars: false,
            audioCodec: "aac",
            presentCapable: true
        ))
        XCTAssertEqual(route, .compatibilityRemux(reason: "container.mkv"))
    }

    func testMKVEAC3UsesRemuxForWatchQualityWhenPresentCapable() {
        // Software-blit DirectMpv is too soft/low-FPS for normal watch; remux + AVPlayer.
        let route = PlaybackRoutePlanner.route(from: .init(
            pathExtension: "mkv",
            mpvAvailable: true,
            remuxAvailable: true,
            videoCodecTag: "h264",
            hasSidecars: false,
            audioCodec: "eac3",
            presentCapable: true
        ))
        XCTAssertEqual(route, .compatibilityRemux(reason: "container.mkv"))
    }

    func testMKVEAC3FallsBackToRemuxWhenPresentNotCapable() {
        let route = PlaybackRoutePlanner.route(from: .init(
            pathExtension: "mkv",
            mpvAvailable: true,
            remuxAvailable: true,
            videoCodecTag: "h264",
            hasSidecars: false,
            audioCodec: "eac3",
            presentCapable: false
        ))
        XCTAssertEqual(route, .compatibilityRemux(reason: "container.mkv"))
    }

    func testOversizedSourcePrefersDirectMpvWhenPresentCapable() {
        let route = PlaybackRoutePlanner.route(from: .init(
            pathExtension: "mkv",
            mpvAvailable: true,
            remuxAvailable: true,
            videoCodecTag: "h264",
            hasSidecars: false,
            audioCodec: "aac",
            sourceBytes: RemuxCacheEviction.maxFullRemuxRetainBytes + 1,
            presentCapable: true
        ))
        XCTAssertEqual(route, .directMpv(reason: "source.oversized"))
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

    func testBitmapOnlySubsPreferDirectMpvWhenPresentCapable() {
        // Auto DirectMpv at open is off while present is software blit (soft picture).
        XCTAssertFalse(BitmapSubtitleRouting.prefersDirectMpvAtOpen)
        let route = PlaybackRoutePlanner.route(from: .init(
            pathExtension: "mkv",
            mpvAvailable: true,
            remuxAvailable: true,
            videoCodecTag: "h264",
            hasSidecars: false,
            subtitleCodecs: ["hdmv_pgs_subtitle", "hdmv_pgs_subtitle"],
            presentCapable: true
        ))
        XCTAssertEqual(route, .compatibilityRemux(reason: "container.mkv"))
    }

    func testBitmapOnlySubsFallBackToRemuxWhenPresentNotCapable() {
        let route = PlaybackRoutePlanner.route(from: .init(
            pathExtension: "mkv",
            mpvAvailable: true,
            remuxAvailable: true,
            videoCodecTag: nil,
            hasSidecars: false,
            subtitleCodecs: ["hdmv_pgs_subtitle"],
            presentCapable: false
        ))
        XCTAssertEqual(route, .compatibilityRemux(reason: "container.mkv"))
    }

    func testPresentInitFailureFallsBackToRemux() {
        let route = BitmapSubtitleRouting.fallbackAfterPresentInitFailure(remuxAvailable: true)
        XCTAssertEqual(route, .compatibilityRemux(reason: "bitmap.presentInitFailed"))
    }

    func testOpenTimeBitmapDecisionDoesNotDependOnLaterPicker() {
        // Remux session for text-capable file stays remux even if codecs list is empty
        // (mid-play PGS pick is a UX tip / restart — not a silent re-route).
        let openRoute = PlaybackRoutePlanner.route(from: .init(
            pathExtension: "mkv",
            mpvAvailable: true,
            remuxAvailable: true,
            videoCodecTag: nil,
            hasSidecars: false,
            subtitleCodecs: ["subrip"],
            presentCapable: true
        ))
        XCTAssertEqual(openRoute, .compatibilityRemux(reason: "container.mkv"))
        XCTAssertFalse(
            BitmapSubtitleRouting.shouldPreferDirectMpv(
                subtitleCodecs: ["subrip"],
                presentCapable: true,
                remuxAvailable: true,
                mpvAvailable: true
            )
        )
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
