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

    func testProgressivePreviewSkippedWhenAudioWouldFullFileTranscode() {
        XCTAssertTrue(FFmpegVideoFallback.shouldSkipProgressivePreview(audioCodec: "ac3"))
        XCTAssertTrue(FFmpegVideoFallback.shouldSkipProgressivePreview(audioCodec: "eac3"))
        XCTAssertFalse(FFmpegVideoFallback.shouldSkipProgressivePreview(audioCodec: "aac"))
        XCTAssertFalse(FFmpegVideoFallback.shouldSkipProgressivePreview(audioCodec: nil))
    }

    func testPreviewByteReadinessRejectsStubHeader() {
        XCTAssertFalse(FFmpegProbeParser.isPreviewByteReady(fileSize: 1032, containsMOOF: false))
        XCTAssertFalse(FFmpegProbeParser.isPreviewByteReady(fileSize: 128 * 1024, containsMOOF: false))
        XCTAssertFalse(FFmpegProbeParser.isPreviewByteReady(fileSize: 1032, containsMOOF: true))
        XCTAssertTrue(FFmpegProbeParser.isPreviewByteReady(fileSize: 128 * 1024, containsMOOF: true))
    }
}
