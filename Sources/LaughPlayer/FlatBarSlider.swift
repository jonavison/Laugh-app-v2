import AppKit
import QuartzCore

/// Semantic full-track gradient for color / tone axes (Lightroom-style).
enum FlatBarSemanticTrack: Equatable {
    case temperature
    case tint
    case hue
    case saturation
    case vibrance
    case colorBalance
    case splitHighlight
    case splitShadow
    case blackAndWhiteAmount
    case blackAndWhiteWarmth

    /// Soft mid, vivid ends — tuned for light/dark. Locations bias chroma into the tips.
    func colors(appearance: NSAppearance) -> [NSColor] {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch self {
        case .temperature:
            // Real ice-blue / amber tips (sRGB), not muted pastels.
            return [
                NSColor(srgbRed: isDark ? 0.20 : 0.18, green: isDark ? 0.52 : 0.55, blue: 1.0, alpha: 1),
                neutralMid(isDark: isDark),
                NSColor(srgbRed: 1.0, green: isDark ? 0.52 : 0.55, blue: isDark ? 0.08 : 0.10, alpha: 1)
            ]
        case .tint:
            return [
                NSColor(srgbRed: isDark ? 0.12 : 0.15, green: isDark ? 0.88 : 0.78, blue: isDark ? 0.32 : 0.35, alpha: 1),
                neutralMid(isDark: isDark),
                NSColor(srgbRed: isDark ? 0.92 : 0.88, green: isDark ? 0.22 : 0.28, blue: isDark ? 0.78 : 0.72, alpha: 1)
            ]
        case .hue:
            return [
                NSColor(srgbRed: 0.92, green: 0.22, blue: 0.22, alpha: 1),
                NSColor(srgbRed: 0.95, green: 0.72, blue: 0.12, alpha: 1),
                NSColor(srgbRed: 0.22, green: 0.82, blue: 0.32, alpha: 1),
                NSColor(srgbRed: 0.15, green: 0.68, blue: 0.95, alpha: 1),
                NSColor(srgbRed: 0.42, green: 0.28, blue: 0.92, alpha: 1),
                NSColor(srgbRed: 0.90, green: 0.22, blue: 0.72, alpha: 1)
            ]
        case .saturation:
            return [
                NSColor(srgbRed: isDark ? 0.45 : 0.68, green: isDark ? 0.45 : 0.68, blue: isDark ? 0.45 : 0.68, alpha: 1),
                NSColor(srgbRed: 0.95, green: 0.20, blue: 0.40, alpha: 1)
            ]
        case .vibrance:
            return [
                NSColor(srgbRed: isDark ? 0.45 : 0.68, green: isDark ? 0.45 : 0.68, blue: isDark ? 0.45 : 0.68, alpha: 1),
                NSColor(srgbRed: 0.20, green: 0.78, blue: 0.88, alpha: 1),
                NSColor(srgbRed: 0.95, green: 0.35, blue: 0.65, alpha: 1)
            ]
        case .colorBalance:
            return [
                NSColor(srgbRed: isDark ? 0.20 : 0.18, green: isDark ? 0.52 : 0.55, blue: 1.0, alpha: 1),
                neutralMid(isDark: isDark),
                NSColor(srgbRed: 1.0, green: isDark ? 0.52 : 0.55, blue: isDark ? 0.08 : 0.10, alpha: 1)
            ]
        case .splitHighlight:
            return [
                NSColor(srgbRed: 0.45, green: 0.70, blue: 1.0, alpha: 1),
                soft(h: 0.10, s: 0.03, b: isDark ? 0.80 : 0.94),
                NSColor(srgbRed: 1.0, green: 0.78, blue: 0.35, alpha: 1)
            ]
        case .splitShadow:
            return [
                NSColor(srgbRed: 0.25, green: 0.40, blue: 0.85, alpha: 1),
                soft(h: 0, s: 0, b: isDark ? 0.44 : 0.58),
                NSColor(srgbRed: 0.85, green: 0.45, blue: 0.20, alpha: 1)
            ]
        case .blackAndWhiteAmount:
            return [
                NSColor(srgbRed: 0.90, green: 0.40, blue: 0.35, alpha: 1),
                soft(h: 0, s: 0, b: isDark ? 0.50 : 0.66)
            ]
        case .blackAndWhiteWarmth:
            return [
                NSColor(srgbRed: 0.55, green: 0.68, blue: 0.88, alpha: 1),
                soft(h: 0, s: 0, b: isDark ? 0.56 : 0.72),
                NSColor(srgbRed: 0.88, green: 0.68, blue: 0.40, alpha: 1)
            ]
        }
    }

    /// Bias chroma into the tips so a thin track still reads fully blue / fully warm.
    func locations(for colorCount: Int) -> [CGFloat] {
        switch self {
        case .temperature, .tint, .colorBalance:
            return [0, 0.5, 1]
        case .vibrance, .splitHighlight, .splitShadow, .blackAndWhiteWarmth:
            return [0, 0.5, 1]
        case .saturation, .blackAndWhiteAmount:
            return [0, 1]
        case .hue:
            return [0, 0.2, 0.4, 0.6, 0.8, 1]
        }
    }

    private func soft(h: CGFloat, s: CGFloat, b: CGFloat) -> NSColor {
        NSColor(calibratedHue: h, saturation: s, brightness: b, alpha: 1)
    }

    private func neutralMid(isDark: Bool) -> NSColor {
        soft(h: 0.08, s: 0.02, b: isDark ? 0.55 : 0.90)
    }
}

/// Horizontal slider that draws a flat filled bar. Playback bars hide the thumb; settings params show a small knob.
final class FlatBarSliderCell: NSSliderCell {
    var trackHeight: CGFloat = 3
    var filledColor: NSColor = LaughTheme.playbackAccent
    var unfilledColor: NSColor = .separatorColor.withAlphaComponent(0.55)
    /// Semantic axis style — colors resolved at draw from current appearance.
    var semanticTrack: FlatBarSemanticTrack?
    /// Soft circular thumb on the track. Off for seek/volume; on for settings param bars.
    var showsKnob = false
    /// When true, draws a segment sliding left/right instead of playback progress.
    var isPreparing = false
    /// 0…1 — position of the preparing segment along the track.
    var preparingPhase: CGFloat = 0
    private var isDraggingKnob = false

    var usesSemanticTrack: Bool { semanticTrack != nil }

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

            if usesSemanticTrack {
                drawSemanticTrack(in: bar, gapMinX: gapMinX, gapMaxX: gapMaxX)
                return
            }

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
        let ring = usesSemanticTrack ? NSColor.labelColor : filledColor

        if active {
            let glow = circle.insetBy(dx: -2.5, dy: -2.5)
            ring.withAlphaComponent(0.22).setFill()
            NSBezierPath(ovalIn: glow).fill()
            let path = NSBezierPath(ovalIn: circle)
            (ring.blended(withFraction: 0.5, of: .white) ?? ring).setFill()
            path.fill()
            NSColor.white.setStroke()
            path.lineWidth = 1
            path.stroke()
        } else {
            let path = NSBezierPath(ovalIn: circle)
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            ring.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 1.25
            path.stroke()
        }
    }

    private func drawSemanticTrack(in bar: NSRect, gapMinX: CGFloat, gapMaxX: CGFloat) {
        let appearance = controlView?.effectiveAppearance ?? NSApp.effectiveAppearance
        guard let style = semanticTrack else { return }
        let colors = style.colors(appearance: appearance)
        guard colors.count >= 2 else { return }
        let locations = style.locations(for: colors.count)
        let gradient = NSGradient(colors: colors, atLocations: locations, colorSpace: .sRGB)
            ?? NSGradient(colors: colors)
        guard let gradient else { return }

        let drawSegment: (NSRect) -> Void = { segment in
            guard segment.width > self.trackHeight * 0.55 else { return }
            NSGraphicsContext.saveGraphicsState()
            self.trackPath(for: segment).addClip()
            // Draw in full-bar coords so gradient stops stay aligned across the gap.
            gradient.draw(in: bar, angle: 0)
            NSGraphicsContext.restoreGraphicsState()
        }

        drawSegment(NSRect(
            x: bar.minX,
            y: bar.minY,
            width: max(0, min(gapMinX, bar.maxX) - bar.minX),
            height: bar.height
        ))
        let restStart = max(gapMaxX, bar.minX)
        drawSegment(NSRect(
            x: restStart,
            y: bar.minY,
            width: max(0, bar.maxX - restStart),
            height: bar.height
        ))
    }

    override func startTracking(at startPoint: NSPoint, in controlView: NSView) -> Bool {
        // Double-click the knob (or track) → snap to the param’s default / identity.
        if showsKnob,
           let event = NSApp.currentEvent,
           event.clickCount >= 2,
           let slider = controlView as? NSSlider,
           let reset = slider.parameterResetValue {
            doubleValue = reset
            slider.doubleValue = reset
            isDraggingKnob = false
            controlView.needsDisplay = true
            if let action = slider.action {
                NSApp.sendAction(action, to: slider.target, from: slider)
            }
            return false
        }

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
    private static var parameterResetValueKey: UInt8 = 0

    /// Identity / default for this param. Double-click the knob to restore (edit sliders).
    var parameterResetValue: Double? {
        get { objc_getAssociatedObject(self, &Self.parameterResetValueKey) as? Double }
        set {
            if let newValue {
                objc_setAssociatedObject(
                    self,
                    &Self.parameterResetValueKey,
                    newValue,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            } else {
                objc_setAssociatedObject(
                    self,
                    &Self.parameterResetValueKey,
                    nil,
                    .OBJC_ASSOCIATION_RETAIN_NONATOMIC
                )
            }
        }
    }

    /// Replaces the cell with a flat bar style. Pass `showsKnob: true` for settings param sliders.
    func useFlatBarAppearance(
        trackHeight: CGFloat = 3,
        filledColor: NSColor = LaughTheme.playbackAccent,
        showsKnob: Bool = false
    ) {
        let existingSemantic = flatBarCell?.semanticTrack
        let flat = FlatBarSliderCell()
        flat.minValue = minValue
        flat.maxValue = maxValue
        flat.doubleValue = doubleValue
        flat.isContinuous = isContinuous
        flat.controlSize = controlSize
        flat.trackHeight = trackHeight
        flat.filledColor = filledColor
        flat.semanticTrack = existingSemantic
        flat.showsKnob = showsKnob
        flat.target = target
        flat.action = action
        flat.isBordered = false
        cell = flat
        sliderType = .linear
    }

    /// Color-axis track (temperature, tint, hue, …). Full gradient; knob position only.
    func applySemanticTrack(_ style: FlatBarSemanticTrack, trackHeight: CGFloat = 6) {
        if flatBarCell == nil {
            useFlatBarAppearance(trackHeight: trackHeight, filledColor: .labelColor, showsKnob: true)
        }
        guard let flat = flatBarCell else { return }
        flat.trackHeight = trackHeight
        flat.semanticTrack = style
        flat.showsKnob = true
        needsDisplay = true
    }

    var flatBarCell: FlatBarSliderCell? {
        cell as? FlatBarSliderCell
    }
}
