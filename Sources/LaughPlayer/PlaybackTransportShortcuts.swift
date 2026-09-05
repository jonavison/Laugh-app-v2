import AppKit

/// Shared policy for playback seek / volume from keyboard and scroll.
enum PlaybackTransportShortcuts {
    static let standardSeekSeconds: Double = 10
    static let fineSeekSeconds: Double = 1
    static let volumeStep: Float = 0.05

    /// User-intent modifiers only.
    /// Arrow / Home / End keys also set `.numericPad` and `.function` on macOS — those must be ignored
    /// or `flags.isEmpty` never matches and ←→ / ↑↓ appear broken.
    static func chordModifiers(from event: NSEvent) -> NSEvent.ModifierFlags {
        event.modifierFlags.intersection([.command, .option, .control, .shift])
    }

    /// Only block while typing — sliders/popups must not steal ←→ / ↑↓ from playback.
    static func blocksTransportShortcuts(firstResponder: Any?) -> Bool {
        if firstResponder is NSTextView { return true }
        if let field = firstResponder as? NSTextField, field.isEditable { return true }
        return false
    }

    enum ScrollAction: Equatable {
        case volume(Float)
        case seek(Double)
    }

    /// Vertical scroll → volume; horizontal or ⇧+vertical → seek.
    /// Fires on every notch / delta so mouse wheels feel immediate (no long accumulate).
    static func consumeScroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        shiftPressed: Bool,
        hasPreciseDeltas: Bool,
        volumeAccumulator: inout CGFloat,
        seekAccumulator: inout CGFloat
    ) -> ScrollAction? {
        _ = volumeAccumulator
        _ = seekAccumulator

        // Require a clear horizontal bias before treating as seek (Magic Mouse often jitters both axes).
        let preferSeek = shiftPressed || (abs(deltaX) > 0.5 && abs(deltaX) > abs(deltaY) * 1.35)
        if preferSeek {
            let raw = shiftPressed ? deltaY : deltaX
            guard abs(raw) > 0.01 else { return nil }
            if hasPreciseDeltas {
                // Continuous seek while swiping / shift-scrolling.
                return .seek(Double(raw) * 0.4)
            }
            return .seek(raw > 0 ? standardSeekSeconds : -standardSeekSeconds)
        }

        guard abs(deltaY) > 0.01 else { return nil }
        if hasPreciseDeltas {
            // Continuous volume — small trackpad moves still register.
            return .volume(Float(deltaY) * 0.025)
        }
        return .volume(deltaY > 0 ? volumeStep : -volumeStep)
    }
}
