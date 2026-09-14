import AVFoundation
import Foundation

/// In-process A→B→C switch / resume / duration harness.
/// Enable with `LAUGH_SWITCH_STRESS=1` and pass sibling paths via env:
///   LAUGH_SWITCH_MEDIA_B, LAUGH_SWITCH_MEDIA_C
/// Optional expected durations (seconds):
///   LAUGH_SWITCH_EXPECT_A, LAUGH_SWITCH_EXPECT_B, LAUGH_SWITCH_EXPECT_C
enum PlaybackSwitchStressHarness {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LAUGH_SWITCH_STRESS"] == "1"
    }

    struct Snapshot {
        var sourceName: String
        var currentSec: Double
        var durationSec: Double
        var rate: Float
        var resumeSec: Double?
    }

    @MainActor
    static func run(
        generation: Int,
        currentGeneration: @escaping () -> Int,
        currentSourceURL: @escaping () -> URL?,
        loadVideo: @escaping (URL) -> Void,
        seekBySeconds: @escaping (Double) -> Void,
        playbackRate: @escaping () -> Float,
        currentTimeSec: @escaping () -> Double,
        durationSec: @escaping () -> Double
    ) async {
        guard isEnabled else { return }
        PlaybackTrace.emit("[DEBUG-switchstress] starting in-app switch harness")

        guard let mediaB = envURL("LAUGH_SWITCH_MEDIA_B"),
              let mediaC = envURL("LAUGH_SWITCH_MEDIA_C") else {
            PlaybackTrace.emit("[DEBUG-switchstress] FAIL missing LAUGH_SWITCH_MEDIA_B/C")
            return
        }
        let expectA = envDouble("LAUGH_SWITCH_EXPECT_A")
        let expectB = envDouble("LAUGH_SWITCH_EXPECT_B")
        let expectC = envDouble("LAUGH_SWITCH_EXPECT_C")

        // Wait for first file to settle.
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        guard generation == currentGeneration() else {
            PlaybackTrace.emit("[DEBUG-switchstress] aborted stale generation")
            return
        }
        guard let mediaA = currentSourceURL() else {
            PlaybackTrace.emit("[DEBUG-switchstress] FAIL no current source")
            return
        }

        var failures = 0
        func fail(_ msg: String) {
            failures += 1
            PlaybackTrace.emit("[DEBUG-switchstress] FAIL \(msg)")
        }
        func ok(_ msg: String) {
            PlaybackTrace.emit("[DEBUG-switchstress] OK \(msg)")
        }

        func snap(_ label: String) -> Snapshot {
            let url = currentSourceURL()
            let name = url?.lastPathComponent ?? "(nil)"
            let cur = currentTimeSec()
            let dur = durationSec()
            let rate = playbackRate()
            let resume = url.flatMap { PlaybackResumeStore.resumeSeconds(for: $0) }
            PlaybackTrace.emit(String(
                format: "[DEBUG-switchstress] snap %@ source=%@ t=%.1f dur=%.1f rate=%.2f resume=%@",
                label,
                name,
                cur,
                dur,
                rate,
                resume.map { String(format: "%.1f", $0) } ?? "nil"
            ))
            return Snapshot(
                sourceName: name,
                currentSec: cur,
                durationSec: dur,
                rate: rate,
                resumeSec: resume
            )
        }

        func waitReady(for url: URL, expectedDuration: Double?, timeoutSec: Double, label: String) async -> Bool {
            let start = CFAbsoluteTimeGetCurrent()
            let path = url.standardizedFileURL.path
            while CFAbsoluteTimeGetCurrent() - start < timeoutSec {
                guard currentGeneration() >= generation else { return false }
                let current = currentSourceURL()?.standardizedFileURL.path
                let dur = durationSec()
                let rate = playbackRate()
                let t = currentTimeSec()
                let sourceOK = current == path
                let durationOK: Bool = {
                    guard let expectedDuration, expectedDuration > 60 else {
                        return dur > 30
                    }
                    // Must be near this file's duration — not the previous episode's.
                    return abs(dur - expectedDuration) <= max(45, expectedDuration * 0.05)
                }()
                let playingOK = rate > 0.05 || t > 0.5
                if sourceOK, durationOK, playingOK {
                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    PlaybackTrace.emit(String(
                        format: "[DEBUG-switchstress] ready %@ in %.2fs dur=%.1f rate=%.2f t=%.1f",
                        label, elapsed, dur, rate, t
                    ))
                    if elapsed > 60 {
                        fail("\(label) ready too slow (\(String(format: "%.1f", elapsed))s > 60s)")
                    } else if elapsed > 45 {
                        PlaybackTrace.emit(String(
                            format: "[DEBUG-switchstress] WARN %@ ready slow %.1fs",
                            label, elapsed
                        ))
                    } else {
                        ok(String(format: "%@ ready in %.1fs", label, elapsed))
                    }
                    return true
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            let dur = durationSec()
            let cur = currentSourceURL()?.lastPathComponent ?? "(nil)"
            fail(String(
                format: "%@ not ready within %ds (source=%@ dur=%.1f rate=%.2f)",
                label, Int(timeoutSec), cur, dur, playbackRate()
            ))
            return false
        }

        func expectDuration(_ got: Double, expected: Double?, label: String, other: Double?) {
            guard let expected, expected > 60 else { return }
            let err = abs(got - expected)
            if got < 30 {
                fail("\(label) duration missing/too small (\(String(format: "%.1f", got)))")
                return
            }
            if err > max(45, expected * 0.05) {
                fail(String(
                    format: "%@ duration %.1f != expected %.1f (err %.1f)",
                    label, got, expected, err
                ))
            } else {
                ok(String(format: "%@ duration≈%.0fs", label, got))
            }
            // Cross-file leak: B showing A's duration.
            if let other, abs(expected - other) > 60, abs(got - other) < 15 {
                fail(String(
                    format: "%@ duration %.1f looks like other file's %.1f",
                    label, got, other
                ))
            }
        }

        // --- Phase 1: park on A at ~120s so A has a distinct resume ---
        let a0 = snap("A_initial")
        expectDuration(a0.durationSec, expected: expectA, label: "A_initial", other: expectB)
        seekBySeconds(120 - currentTimeSec())
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let aParked = snap("A_parked")
        if aParked.currentSec < 60 {
            fail(String(format: "A park failed t=%.1f", aParked.currentSec))
        } else {
            ok(String(format: "A parked at %.0fs", aParked.currentSec))
        }

        // --- Phase 2: switch to B ---
        let switchBAt = CFAbsoluteTimeGetCurrent()
        PlaybackTrace.emit("[DEBUG-switchstress] switch → B")
        loadVideo(mediaB)
        guard await waitReady(for: mediaB, expectedDuration: expectB, timeoutSec: 120, label: "B") else {
            PlaybackTrace.emit("[DEBUG-switchstress] DONE failures=\(failures)")
            return
        }
        let b1 = snap("B_after_switch")
        expectDuration(b1.durationSec, expected: expectB, label: "B_after_switch", other: aParked.durationSec)
        // B must not inherit A's parked playhead (unless B's own resume was already ~that).
        if abs(b1.currentSec - aParked.currentSec) < 8, aParked.currentSec > 80 {
            // Allow only if resume store for B already had that value before switch — we cleared by using distinct files.
            fail(String(
                format: "B playhead %.1f looks copied from A park %.1f",
                b1.currentSec, aParked.currentSec
            ))
        } else {
            ok("B playhead not copied from A")
        }
        if b1.rate < 0.05, b1.currentSec < 1 {
            // Still starting is ok briefly; re-check.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let b2 = snap("B_recheck")
            if b2.rate < 0.05 {
                fail("B not playing after switch")
            }
        }
        _ = switchBAt

        // Park B at ~200s
        seekBySeconds(200 - currentTimeSec())
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let bParked = snap("B_parked")

        // --- Phase 3: switch to C ---
        PlaybackTrace.emit("[DEBUG-switchstress] switch → C")
        loadVideo(mediaC)
        guard await waitReady(for: mediaC, expectedDuration: expectC, timeoutSec: 120, label: "C") else {
            PlaybackTrace.emit("[DEBUG-switchstress] DONE failures=\(failures)")
            return
        }
        let c1 = snap("C_after_switch")
        expectDuration(c1.durationSec, expected: expectC, label: "C_after_switch", other: bParked.durationSec)
        if abs(c1.currentSec - bParked.currentSec) < 8, bParked.currentSec > 80 {
            fail(String(
                format: "C playhead %.1f looks copied from B park %.1f",
                c1.currentSec, bParked.currentSec
            ))
        } else {
            ok("C playhead not copied from B")
        }

        // --- Phase 4: return to A — should resume near park (~120) ---
        if ProcessInfo.processInfo.environment["LAUGH_SWITCH_SKIP_A_RETURN"] == "1" {
            PlaybackTrace.emit("[DEBUG-switchstress] skip A return (LAUGH_SWITCH_SKIP_A_RETURN=1)")
            if failures == 0 {
                PlaybackTrace.emit("[DEBUG-switchstress] PASS all checks")
            }
            PlaybackTrace.emit("[DEBUG-switchstress] DONE failures=\(failures)")
            return
        }

        PlaybackTrace.emit("[DEBUG-switchstress] switch → A (resume check)")
        loadVideo(mediaA)
        guard await waitReady(for: mediaA, expectedDuration: expectA, timeoutSec: 120, label: "A_return") else {
            PlaybackTrace.emit("[DEBUG-switchstress] DONE failures=\(failures)")
            return
        }
        // Ready can fire before seek-before-play lands; wait for resumed playhead.
        let resumeDeadline = CFAbsoluteTimeGetCurrent() + 8
        while CFAbsoluteTimeGetCurrent() < resumeDeadline, currentTimeSec() < 60 {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        let aBack = snap("A_return")
        expectDuration(aBack.durationSec, expected: expectA, label: "A_return", other: expectB)
        if let resume = PlaybackResumeStore.resumeSeconds(for: mediaA) {
            if resume < 60 || resume > 400 {
                fail(String(format: "A resume store odd %.1f (want ~120)", resume))
            } else {
                ok(String(format: "A resume store %.0fs", resume))
            }
        }
        // Playhead should be near parked A (resume applied), not near B's 200s.
        if abs(aBack.currentSec - 200) < 15, abs(aParked.currentSec - 200) > 40 {
            fail(String(format: "A return playhead %.1f looks like B park", aBack.currentSec))
        }
        // After C→A, require resumed playhead near park (not start).
        if aBack.currentSec < 60 {
            fail(String(format: "A return playhead %.1f — expected resume near ~120s", aBack.currentSec))
        } else if abs(aBack.currentSec - aParked.currentSec) < 45 {
            ok(String(format: "A resumed near park (t=%.0f)", aBack.currentSec))
        } else {
            PlaybackTrace.emit(String(
                format: "[DEBUG-switchstress] WARN A return t=%.1f vs park %.1f",
                aBack.currentSec, aParked.currentSec
            ))
        }

        // Resume map sanity: B must not store A's duration.
        if let bResume = PlaybackResumeStore.resumeSeconds(for: mediaB),
           let eb = expectB, bResume > eb {
            fail(String(format: "B resume %.1f > B duration %.1f", bResume, eb))
        }

        if failures == 0 {
            PlaybackTrace.emit("[DEBUG-switchstress] PASS all checks")
        }
        PlaybackTrace.emit("[DEBUG-switchstress] DONE failures=\(failures)")
    }

    private static func envURL(_ key: String) -> URL? {
        guard let raw = ProcessInfo.processInfo.environment[key], !raw.isEmpty else { return nil }
        let url = URL(fileURLWithPath: raw)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func envDouble(_ key: String) -> Double? {
        guard let raw = ProcessInfo.processInfo.environment[key], let v = Double(raw), v > 0 else {
            return nil
        }
        return v
    }
}
