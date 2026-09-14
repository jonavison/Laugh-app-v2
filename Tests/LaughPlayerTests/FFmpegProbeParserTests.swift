import XCTest
@testable import LaughPlayer

final class FFmpegProbeParserTests: XCTestCase {
    func testParsesMatroskaH264AC3Probe() {
        let stderr = """
        Input #0, matroska,webm, from 'Bohemian.Rhapsody.mkv':
          Duration: 02:15:19.36, start: 0.000000, bitrate: 4923 kb/s
          Stream #0:0(eng): Video: h264 (High), yuv420p(tv, bt709, progressive), 1920x802 [SAR 1:1 DAR 960:401], 23.98 fps, 23.98 tbr, 1k tbn, start 0.043000 (default)
          Stream #0:1(eng): Audio: ac3, 48000 Hz, 5.1(side), fltp, 384 kb/s (default)
          Stream #0:2: Video: mjpeg (Baseline), yuvj444p(pc, bt470bg/unknown/unknown), 120x176, 90k tbr, 90k tbn (attached pic)
        """
        let summary = FFmpegProbeParser.parse(stderr)
        XCTAssertEqual(summary.videoCodecName, "h264")
        XCTAssertNil(summary.videoCodecTag)
        XCTAssertEqual(summary.audioCodec, "ac3")
        XCTAssertEqual(summary.durationSec ?? 0, 8119.36, accuracy: 0.01)
        XCTAssertTrue(summary.subtitleCodecs.isEmpty)
        XCTAssertTrue(summary.hasAudio)
        XCTAssertTrue(summary.hasVideo)
    }

    func testParsesRemuxedMP4FourCCAndAC3Tag() {
        let stderr = """
        Input #0, mov,mp4,m4a,3gp,3g2,mj2, from 'Bohemian-remux.mp4':
          Duration: 02:15:19.36, start: 0.000000, bitrate: 4929 kb/s
          Stream #0:0[0x1](eng): Video: h264 (High) (avc1 / 0x31637661), yuv420p(tv, bt709, progressive), 1920x802
          Stream #0:1[0x2](eng): Audio: ac3 (ac-3 / 0x332D6361), 48000 Hz, 5.1(side), fltp, 384 kb/s (default)
        """
        let summary = FFmpegProbeParser.parse(stderr)
        XCTAssertEqual(summary.videoCodecName, "h264")
        XCTAssertEqual(summary.videoCodecTag, "avc1")
        XCTAssertEqual(summary.audioCodec, "ac3")
    }

    func testParsesHEVC10BitAndTextSubtitles() {
        let stderr = """
          Duration: 00:01:30.00, start: 0.000000, bitrate: 8000 kb/s
          Stream #0:0: Video: hevc (Main 10) (hev1 / 0x31766568), yuv420p10le
          Stream #0:1: Audio: aac, 48000 Hz, stereo
          Stream #0:2(eng): Subtitle: subrip
          Stream #0:3(eng): Subtitle: ass
        """
        let summary = FFmpegProbeParser.parse(stderr)
        XCTAssertEqual(summary.videoCodecName, "hevc")
        XCTAssertEqual(summary.videoCodecTag, "hev1")
        XCTAssertEqual(summary.audioCodec, "aac")
        XCTAssertEqual(summary.subtitleCodecs, ["subrip", "ass"])
        XCTAssertEqual(summary.durationSec ?? 0, 90, accuracy: 0.01)
    }

    func testDoesNotTreatHighProfileAsFourCC() {
        let stderr = "Stream #0:0: Video: h264 (High), yuv420p"
        XCTAssertNil(FFmpegProbeParser.parseVideoCodecTag(from: stderr))
        XCTAssertEqual(FFmpegProbeParser.parseVideoCodecName(from: stderr), "h264")
    }

    func testFragmentedPreviewTranscodeForDolbyDigital() {
        XCTAssertTrue(FFmpegProbeParser.needsFragmentedAudioTranscode(audioCodec: "eac3"))
        XCTAssertTrue(FFmpegProbeParser.needsFragmentedAudioTranscode(audioCodec: "ec-3"))
        XCTAssertTrue(FFmpegProbeParser.needsFragmentedAudioTranscode(audioCodec: "ac3"))
        XCTAssertTrue(FFmpegProbeParser.needsFragmentedAudioTranscode(audioCodec: "ac-3"))
        XCTAssertFalse(FFmpegProbeParser.needsFragmentedAudioTranscode(audioCodec: "aac"))
        XCTAssertFalse(FFmpegProbeParser.needsFragmentedAudioTranscode(audioCodec: nil))
    }

    func testProgressivePreviewNotSkippedForTranscodeAudio_usesCapInstead() {
        // Uncapped AAC preview used to be skipped; capped progressive is preferred.
        XCTAssertFalse(FFmpegVideoFallback.shouldSkipProgressivePreview(audioCodec: "ac3"))
        XCTAssertFalse(FFmpegVideoFallback.shouldSkipProgressivePreview(audioCodec: "eac3"))
        XCTAssertFalse(FFmpegVideoFallback.shouldSkipProgressivePreview(audioCodec: "aac"))
        XCTAssertFalse(FFmpegVideoFallback.shouldSkipProgressivePreview(audioCodec: nil))
        XCTAssertEqual(FFmpegVideoFallback.audioTranscodePreviewCapSec, 120, accuracy: 0.1)
    }

    func testPreviewByteReadinessRejectsStubHeader() {
        XCTAssertFalse(FFmpegProbeParser.isPreviewByteReady(fileSize: 1032, containsMOOF: false))
        XCTAssertFalse(FFmpegProbeParser.isPreviewByteReady(fileSize: 128 * 1024, containsMOOF: false))
        XCTAssertFalse(FFmpegProbeParser.isPreviewByteReady(fileSize: 1032, containsMOOF: true))
        XCTAssertTrue(FFmpegProbeParser.isPreviewByteReady(fileSize: 128 * 1024, containsMOOF: true))
    }

    func testBitmapOnlySubtitleDetection() {
        let pgs = FFmpegProbeParser.parseSubtitleCodecs(from: """
            Stream #0:2(eng): Subtitle: hdmv_pgs_subtitle (pgssub)
            Stream #0:3(chi): Subtitle: hdmv_pgs_subtitle (pgssub)
            """)
        XCTAssertTrue(FFmpegProbeParser.hasBitmapSubtitlesOnly(codecs: pgs))

        let mixed = FFmpegProbeParser.parseSubtitleCodecs(from: """
            Stream #0:2(eng): Subtitle: subrip (srt)
            Stream #0:3(eng): Subtitle: hdmv_pgs_subtitle (pgssub)
            """)
        XCTAssertFalse(FFmpegProbeParser.hasBitmapSubtitlesOnly(codecs: mixed))
        XCTAssertFalse(FFmpegProbeParser.hasBitmapSubtitlesOnly(codecs: []))
    }

    func testParseSubtitleStreamsKeepsLanguageAndTitle() {
        let streams = FFmpegProbeParser.parseSubtitleStreams(from: """
              Stream #0:2(eng): Subtitle: hdmv_pgs_subtitle (pgssub)
                Metadata:
                  title           : Eng/SUP English
              Stream #0:3(chi): Subtitle: hdmv_pgs_subtitle (pgssub)
                Metadata:
                  title           : Chs/SUP Chinese
            """)
        XCTAssertEqual(streams.count, 2)
        XCTAssertEqual(streams[0].subtitleIndex, 0)
        XCTAssertEqual(streams[0].language, "eng")
        XCTAssertEqual(streams[0].title, "Eng/SUP English")
        XCTAssertEqual(streams[0].codec, "hdmv_pgs_subtitle")
        XCTAssertEqual(streams[1].language, "chi")
        let tracks = SubtitleTrackCatalog.tracks(fromBitmapStreams: streams)
        XCTAssertEqual(tracks.count, 2)
        guard case .embeddedBitmapOverlay(let index) = tracks[0].backendID else {
            return XCTFail("expected embeddedBitmapOverlay")
        }
        XCTAssertEqual(index, 0)
        XCTAssertTrue(tracks[0].menuTitle.contains("Eng/SUP English"))
    }

    func testRemuxPayloadRejectsSparseOutput() {
        // Bourne Identity: 146MB remux of a 1.7GB source — duration OK, payload empty → seek freezes.
        XCTAssertFalse(
            FFmpegProbeParser.remuxPayloadLooksComplete(
                outputBytes: 146_000_000,
                sourceBytes: 1_700_000_000
            )
        )
        // Dropping commentary can land near ~45–60%; that must still pass the size gate
        // (fps / source-sparse checks catch the real incomplete-torrent cases).
        XCTAssertTrue(
            FFmpegProbeParser.remuxPayloadLooksComplete(
                outputBytes: 764_251_444,
                sourceBytes: 1_692_150_810
            )
        )
        XCTAssertTrue(
            FFmpegProbeParser.remuxPayloadLooksComplete(
                outputBytes: 1_400_000_000,
                sourceBytes: 1_700_000_000
            )
        )
        // Tiny sources skip the ratio gate.
        XCTAssertTrue(
            FFmpegProbeParser.remuxPayloadLooksComplete(outputBytes: 50_000, sourceBytes: 80_000)
        )
    }

    func testRemuxFrameRateRejectsSparseAverageFps() {
        // Supremacy sparse remux: `11.25 fps, 23.98 tbr`
        XCTAssertFalse(
            FFmpegProbeParser.remuxFrameRateLooksComplete(averageFps: 11.25, containerFps: 23.98)
        )
        // Jason Bourne poisoned remux: ~19.97/23.92 — still freezes late in timeline.
        XCTAssertFalse(
            FFmpegProbeParser.remuxFrameRateLooksComplete(averageFps: 19.97, containerFps: 23.92)
        )
        XCTAssertTrue(
            FFmpegProbeParser.remuxFrameRateLooksComplete(averageFps: 23.98, containerFps: 23.98)
        )
        // Missing probe data does not fail open playback.
        XCTAssertTrue(
            FFmpegProbeParser.remuxFrameRateLooksComplete(averageFps: nil, containerFps: 23.98)
        )

        let sparseLine = """
        Stream #0:0: Video: hevc (Main) (hvc1 / 0x31637668), yuv420p, 1920x816, 815 kb/s, 11.25 fps, 23.98 tbr, 16k tbn
        """
        XCTAssertEqual(FFmpegProbeParser.parseVideoAverageFps(from: sparseLine) ?? -1, 11.25, accuracy: 0.01)
        XCTAssertEqual(FFmpegProbeParser.parseVideoContainerFps(from: sparseLine) ?? -1, 23.98, accuracy: 0.01)
    }
}
