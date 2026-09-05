import AppKit

/// Flipped document view so Auto Layout content grows downward inside `NSScrollView`.
final class SettingsScrollDocumentView: NSView {
    override var isFlipped: Bool { true }
}
