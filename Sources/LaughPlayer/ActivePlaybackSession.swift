import AVFoundation
import Foundation

protocol ActivePlaybackSession: AnyObject {
    var isPlaying: Bool { get }
    var currentTimeSec: Double { get }
    var durationSec: Double { get }
    func play()
    func pause()
    func seek(to seconds: Double, exact: Bool, completion: ((Bool) -> Void)?)
    func setRate(_ rate: Float)
    func setVolume(_ linear0to1: Float)
}

final class AVPlayerPlaybackSession: ActivePlaybackSession {
    private let player: AVPlayer

    init(player: AVPlayer) {
        self.player = player
    }

    var isPlaying: Bool { player.rate > 0 }

    var currentTimeSec: Double {
        let sec = CMTimeGetSeconds(player.currentTime())
        return sec.isFinite ? max(0, sec) : 0
    }

    var durationSec: Double {
        guard let item = player.currentItem else { return 0 }
        let sec = CMTimeGetSeconds(item.duration)
        return sec.isFinite ? max(0, sec) : 0
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: Double, exact: Bool, completion: ((Bool) -> Void)?) {
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = exact ? CMTime.zero : CMTime(seconds: 0.5, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance) { finished in
            DispatchQueue.main.async { completion?(finished) }
        }
    }

    func setRate(_ rate: Float) {
        player.defaultRate = rate
        if player.rate > 0 {
            player.rate = rate
        }
    }

    func setVolume(_ linear0to1: Float) {
        player.volume = linear0to1
        player.isMuted = linear0to1 < 0.01
    }
}

final class MpvPlaybackSession: ActivePlaybackSession {
    private let controller: MpvPlaybackController
    private var paused = true

    init(controller: MpvPlaybackController) {
        self.controller = controller
        controller.onPauseChanged = { [weak self] pause in
            self?.paused = pause
        }
    }

    var isPlaying: Bool { !paused && controller.isRunning }

    var currentTimeSec: Double { controller.currentTimeSec() }
    var durationSec: Double { controller.durationSec() }

    func play() {
        paused = false
        controller.play()
    }

    func pause() {
        paused = true
        controller.pause()
    }

    func seek(to seconds: Double, exact: Bool, completion: ((Bool) -> Void)?) {
        controller.seek(to: seconds, exact: exact)
        DispatchQueue.main.async { completion?(true) }
    }

    func setRate(_ rate: Float) {
        controller.setSpeed(rate)
    }

    func setVolume(_ linear0to1: Float) {
        controller.setVolume(linear0to1)
    }
}
