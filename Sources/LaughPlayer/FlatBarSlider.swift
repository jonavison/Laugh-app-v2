import AppKit
import QuartzCore

/// Horizontal slider that draws a flat filled bar. Playback bars hide the thumb; settings params show a small knob.
final class FlatBarSliderCell: NSSliderCell {
    var trackHeight: CGFloat = 3
    var filledColor: NSColor = LaughTheme.playbackAccent
    var unfilledColor: NSColor = .separatorColor.withAlphaComponent(0.55)
    /// Soft circular thumb on the track. Off for seek/volume; on for settings param bars.
    var showsKnob = false
    /// When true, draws a segment sliding left/right instead of playback progress.
    var isPreparing = false
    /// 0…1 — position of the preparing segment along the track.
    var preparingPhase: CGFloat = 0
    private var isDraggingKnob = false

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

        if isPreparing {
            let track = trackPath(for: bar)
            unfilledColor.setFill()
            track.fill()
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

        // Settings thumbs: leave a clear air gap so the knob floats between the
        // filled and unfilled track (----- O -----) instead of sitting on it (-O----).
        if showsKnob {
            let active = isDraggingKnob || isHighlighted
            let diameter: CGFloat = active ? 13 : 11
            let gapPad: CGFloat = 3.5
            let travel = max(0, bar.width - diameter)
            let knobCenterX = bar.minX + diameter / 2 + progress * travel
            let gapMinX = knobCenterX - diameter / 2 - gapPad
            let gapMaxX = knobCenterX + diameter / 2 + gapPad

            let fillEnd = min(gapMinX, bar.maxX)
            if fillEnd - bar.minX > trackHeight * 0.6 {
                let fillBar = NSRect(
                    x: bar.minX,
                    y: bar.minY,
                    width: fillEnd - bar.minX,
                    height: bar.height
                )
                filledColor.setFill()
                trackPath(for: fillBar).fill()
            }

            let restStart = max(gapMaxX, bar.minX)
            if bar.maxX - restStart > trackHeight * 0.6 {
                let restBar = NSRect(
                    x: restStart,
                    y: bar.minY,
                    width: bar.maxX - restStart,
                    height: bar.height
                )
                unfilledColor.setFill()
                trackPath(for: restBar).fill()
            }
            return
        }

        // Playback bars: continuous track under a hidden thumb.
        let track = trackPath(for: bar)
        unfilledColor.setFill()
        track.fill()
        guard progress > 0 else { return }
        let fillWidth = max(trackHeight, bar.width * progress)
        let fillBar = NSRect(x: bar.minX, y: bar.minY, width: fillWidth, height: bar.height)
        filledColor.setFill()
        trackPath(for: fillBar).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        guard showsKnob, !isPreparing else { return }
        let active = isDraggingKnob || isHighlighted
        let diameter: CGFloat = active ? 13 : 11
        let circle = NSRect(
            x: knobRect.midX - diameter / 2,
            y: knobRect.midY - diameter / 2,
            width: diameter,
            height: diameter
        )

        if active {
            let glow = circle.insetBy(dx: -2.5, dy: -2.5)
            filledColor.withAlphaComponent(0.28).setFill()
            NSBezierPath(ovalIn: glow).fill()
            let path = NSBezierPath(ovalIn: circle)
            filledColor.blended(withFraction: 0.45, of: .white)?.setFill()
            path.fill()
            NSColor.white.setStroke()
            path.lineWidth = 1
            path.stroke()
        } else {
            let path = NSBezierPath(ovalIn: circle)
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            filledColor.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 1.25
            path.stroke()
        }
    }

    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
        isDraggingKnob = true
        controlView.needsDisplay = true
        return super.startTracking(at: startPoint, in: controlView)
    }

    override func continueTracking(last lastPoint: NSPoint, current currentPoint: NSPoint, in controlView: NSView) -> Bool {
        controlView.needsDisplay = true
        return super.continueTracking(last: lastPoint, current: currentPoint, in: controlView)
    }

    override func stopTracking(last lastPoint: NSPoint, current stopPoint: NSPoint, in controlView: NSView, mouseIsUp flag: Bool) {
        isDraggingKnob = false
        controlView.needsDisplay = true
        super.stopTracking(last: lastPoint, current: stopPoint, in: controlView, mouseIsUp: flag)
    }

    override func knobRect(flipped: Bool) -> NSRect {
        let bar = barRect(flipped: flipped)
        let progress = normalizedProgress
        // Center the thumb on the progress point so the track gap lines up with it.
        let knobSize: CGFloat = showsKnob ? 20 : 10
        let knobHeight = showsKnob ? knobSize : max(trackHeight + 10, 18)
        if showsKnob {
            let diameter: CGFloat = 13
            let travel = max(0, bar.width - diameter)
            let centerX = bar.minX + diameter / 2 + progress * travel
            return NSRect(
                x: centerX - knobSize / 2,
                y: bar.midY - knobHeight / 2,
                width: knobSize,
                height: knobHeight
            )
        }
        let x = bar.minX + progress * max(0, bar.width - knobSize)
        return NSRect(
            x: x,
            y: bar.midY - knobHeight / 2,
            width: knobSize,
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
    /// Replaces the cell with a flat bar style. Pass `showsKnob: true` for settings param sliders.
    func useFlatBarAppearance(
        trackHeight: CGFloat = 3,
        filledColor: NSColor = LaughTheme.playbackAccent,
        showsKnob: Bool = false
    ) {
        let flat = FlatBarSliderCell()
        flat.minValue = minValue
        flat.maxValue = maxValue
        flat.doubleValue = doubleValue
        flat.isContinuous = isContinuous
        flat.controlSize = controlSize
        flat.trackHeight = trackHeight
        flat.filledColor = filledColor
        flat.showsKnob = showsKnob
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
