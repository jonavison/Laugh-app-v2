import AVFoundation
import Foundation

/// In-process ←/→ seek hammer. Enabled with `LAUGH_SEEK_STRESS=1`.
/// Avoids Accessibility / osascript — drives `commandSeek` on the main actor directly.
enum PlaybackSeekStressHarness {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["LAUGH_SEEK_STRESS"] == "1"
    }

    @MainActor
    static func run(
        generation: Int,
        currentGeneration: @escaping () -> Int,
        seekBySeconds: @escaping (Double) -> Void,
        playbackRate: @escaping () -> Float,
        currentTimeSec: @escaping () -> Double
    ) async {
        guard isEnabled else { return }
        PlaybackTrace.emit("[DEBUG-seekstress] starting in-app seek harness")
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard generation == currentGeneration() else {
            PlaybackTrace.emit("[DEBUG-seekstress] aborted stale generation")
            return
        }

        func snapshot(_ label: String) {
            let rate = playbackRate()
            let t = currentTimeSec()
            PlaybackTrace.emit(String(
                format: "[DEBUG-seekstress] %@ rate=%.2f t=%.2f",
                label, rate, t
            ))
            if rate < 0.01 {
                PlaybackTrace.emit("[DEBUG-seekstress] FAIL stuck-paused after \(label)")
            } else {
                PlaybackTrace.emit("[DEBUG-seekstress] OK playing after \(label)")
            }
        }

        func burst(label: String, seconds: Double, count: Int, gapNs: UInt64) async {
            PlaybackTrace.emit("[DEBUG-seekstress] burst \(label) count=\(count) delta=\(seconds)s")
            for _ in 0..<count {
                guard generation == currentGeneration() else { return }
                seekBySeconds(seconds)
                try? await Task.sleep(nanoseconds: gapNs)
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            snapshot(label)
        }

        await burst(label: "forward_x20", seconds: 10, count: 20, gapNs: 150_000_000)
        await burst(label: "back_x20", seconds: -10, count: 20, gapNs: 150_000_000)

        PlaybackTrace.emit("[DEBUG-seekstress] burst alternating_x40")
        for _ in 0..<40 {
            guard generation == currentGeneration() else { return }
            seekBySeconds(10)
            try? await Task.sleep(nanoseconds: 100_000_000)
            seekBySeconds(-10)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        snapshot("alternating_x40")

        await burst(label: "rapid_forward_x50", seconds: 10, count: 50, gapNs: 50_000_000)
        await burst(label: "rapid_back_x50", seconds: -10, count: 50, gapNs: 50_000_000)

        // Absolute jumps like seek-bar clicks (not ±10 arrow nudges).
        PlaybackTrace.emit("[DEBUG-seekstress] burst seekbar_abs_x30")
        let absTargets: [Double] = [
            1200, 60, 2400, 300, 900, 150, 1800, 450, 2100, 30,
            1100, 700, 1600, 80, 500, 2000, 250, 1300, 100, 800,
            1700, 400, 1000, 50, 2200, 600, 1400, 200, 1900, 350
        ]
        for target in absTargets {
            guard generation == currentGeneration() else { return }
            seekBySeconds(target - currentTimeSec())
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        snapshot("seekbar_abs_x30")

        try? await Task.sleep(nanoseconds: 4_000_000_000)
        snapshot("final_idle")
        PlaybackTrace.emit("[DEBUG-seekstress] DONE")
    }
}
