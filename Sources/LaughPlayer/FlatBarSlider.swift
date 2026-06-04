import AppKit
import QuartzCore

/// Horizontal slider that draws a flat filled bar without the default round knob.
final class FlatBarSliderCell: NSSliderCell {
    var trackHeight: CGFloat = 3
    var filledColor: NSColor = LaughTheme.playbackAccent
    var unfilledColor: NSColor = .separatorColor.withAlphaComponent(0.55)
    /// When true, draws a segment sliding left/right instead of playback progress.
    var isPreparing = false
    /// 0…1 — position of the preparing segment along the track.
    var preparingPhase: CGFloat = 0

    override func barRect(flipped: Bool) -> NSRect {
        let rect = super.barRect(flipped: flipped)
        return NSRect(
            x: rect.minX,
            y: rect.midY - trackHeight / 2,
            width: rect.width,
            height: trackHeight
        )
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let bar = barRect(flipped: flipped)
        guard bar.width > 1 else { return }

        let track = trackPath(for: bar)
        unfilledColor.setFill()
        track.fill()

        if isPreparing {
            let segmentFraction: CGFloat = 0.22
            let travel = max(0, 1 - segmentFraction)
            let start = preparingPhase * travel
            let segmentWidth = max(trackHeight * 2, bar.width * segmentFraction)
            let segment = NSRect(
                x: bar.minX + bar.width * start,
                y: bar.minY,
                width: segmentWidth,
                height: bar.height
            )
            let pulse = trackPath(for: segment)
            filledColor.withAlphaComponent(0.9).setFill()
            pulse.fill()
            return
        }

        let progress = normalizedProgress
        guard progress > 0 else { return }

        let fillWidth = max(trackHeight, bar.width * progress)
        let fillBar = NSRect(x: bar.minX, y: bar.minY, width: fillWidth, height: bar.height)
        let fill = trackPath(for: fillBar)
        filledColor.setFill()
        fill.fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        // Intentionally empty — no round thumb.
    }

    override func knobRect(flipped: Bool) -> NSRect {
        let bar = barRect(flipped: flipped)
        let progress = normalizedProgress
        let knobWidth: CGFloat = 10
        let knobHeight = max(trackHeight + 10, 18)
        let x = bar.minX + progress * max(0, bar.width - knobWidth)
        return NSRect(
            x: x,
            y: bar.midY - knobHeight / 2,
            width: knobWidth,
            height: knobHeight
        )
    }

    private var normalizedProgress: CGFloat {
        guard maxValue > minValue else { return 0 }
        let value = (doubleValue - minValue) / (maxValue - minValue)
        return CGFloat(max(0, min(1, value)))
    }

    private func trackPath(for rect: NSRect) -> NSBezierPath {
        let radius = min(trackHeight / 2, rect.height / 2)
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}

extension NSSlider {
    /// Replaces the cell with a flat bar style (no round white knob).
    func useFlatBarAppearance(trackHeight: CGFloat = 3, filledColor: NSColor = LaughTheme.playbackAccent) {
        let flat = FlatBarSliderCell()
        flat.minValue = minValue
        flat.maxValue = maxValue
        flat.doubleValue = doubleValue
        flat.isContinuous = isContinuous
        flat.controlSize = controlSize
        flat.trackHeight = trackHeight
        flat.filledColor = filledColor
        flat.target = target
        flat.action = action
        flat.isBordered = false
        cell = flat
        sliderType = .linear
    }

    var flatBarCell: FlatBarSliderCell? {
        cell as? FlatBarSliderCell
    }
}
