import AVFoundation
import CoreVideo

/// Detects CompatibilityFailure cases where audio plays but video frames are missing or black.
final class PlaybackRenderMonitor {
    private var videoOutput: AVPlayerItemVideoOutput?
    private weak var attachedItem: AVPlayerItem?
    private var workItem: DispatchWorkItem?
    private var didReport = false
    var videoCodecFourCC: String?

    func reset() {
        workItem?.cancel()
        if let item = attachedItem, let output = videoOutput {
            item.remove(output)
        }
        videoOutput = nil
        attachedItem = nil
        didReport = false
    }

    func beginMonitoring(player: AVPlayer, item: AVPlayerItem, onRenderFailure: @escaping (String) -> Void) {
        reset()

        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        item.add(output)
        videoOutput = output
        attachedItem = item

        let work = DispatchWorkItem { [weak self, weak player] in
            guard let self, let player, !self.didReport else { return }
            guard player.rate > 0 else { return }
            if !item.isPlaybackLikelyToKeepUp && item.isPlaybackBufferEmpty {
                print("[DEBUG-qos] render_monitor skipped: buffer still empty at check time")
                return
            }

            let time = item.currentTime()
            guard CMTimeGetSeconds(time) > 0.75 else { return }

            let message: String?
            if !self.hasVideoFrame(at: time) {
                message = self.failureMessage(
                    headline: "No video frames were rendered (audio may still play)."
                )
            } else if self.isLikelyBlackFrame(at: time) {
                message = self.failureMessage(
                    headline: "Video is playing audio but the picture appears black."
                )
            } else {
                message = nil
            }

            guard let message else { return }
            self.didReport = true
            DispatchQueue.main.async {
                onRenderFailure(message)
            }
        }
        workItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: work)
    }

    private func hasVideoFrame(at time: CMTime) -> Bool {
        guard let output = videoOutput else { return false }
        return output.hasNewPixelBuffer(forItemTime: time)
    }

    private func isLikelyBlackFrame(at time: CMTime) -> Bool {
        guard let output = videoOutput,
              output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
            return false
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return false }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0 else { return false }

        var sum: UInt64 = 0
        var samples = 0
        let stepX = max(1, width / 32)
        let stepY = max(1, height / 32)

        for y in stride(from: 0, to: height, by: stepY) {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: 0, to: width, by: stepX) {
                let offset = x * 4
                let b = UInt64(row[offset])
                let g = UInt64(row[offset + 1])
                let r = UInt64(row[offset + 2])
                sum += (r + g + b) / 3
                samples += 1
            }
        }

        let average = Double(sum) / Double(max(samples, 1))
        return average < 8.0
    }

    private func failureMessage(headline: String) -> String {
        var text = headline
        text += "\n\nNative macOS playback could not render this video."

        if videoCodecFourCC == "hev1" {
            text += "\n\nThis file may use HEVC (hev1). Try remuxing without re-encoding:\nffmpeg -i input.mp4 -c copy -tag:v hvc1 output.mp4"
        } else if let codec = videoCodecFourCC {
            text += "\n\nDetected video codec: \(codec)."
        }

        text += "\n\nTrying bundled compatibility decoder..."
        return text
    }
}
