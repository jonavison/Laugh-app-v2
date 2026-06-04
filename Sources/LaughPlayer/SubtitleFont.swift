import AppKit
import CoreText
import Foundation

/// Bundled [Geist](https://vercel.com/font) (SIL OFL) for on-screen subtitles.
enum SubtitleFont {
    /// ASS / libass `Fontname` field.
    static let assFontName = "Geist SemiBold"
    /// mpv `sub-font` family name.
    static let mpvFontName = "Geist"
    /// PostScript name of the bundled OTF.
    static let postScriptName = "Geist-SemiBold"
    private static let resourceName = "Geist-SemiBold"
    private static let resourceExtension = "otf"
    private static var didRegister = false

    /// Registers the bundled font with Core Text for this process (safe to call repeatedly).
    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        guard let url = bundledFontURL else {
            print("[DEBUG-subs] Geist font not found in bundle")
            return
        }
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !ok, let message = error?.takeRetainedValue().localizedDescription {
            print("[DEBUG-subs] Geist registration failed: \(message)")
        }
    }

    static func nsFont(size: CGFloat) -> NSFont {
        registerIfNeeded()
        if let font = NSFont(name: postScriptName, size: size) {
            return font
        }
        if let font = NSFont(name: assFontName, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    /// Directory containing bundled subtitle fonts (for mpv `--sub-fonts-dir`).
    static var bundledFontsDirectoryURL: URL? {
        bundledFontURL?.deletingLastPathComponent()
    }

    private static var bundledFontURL: URL? {
        if let url = Bundle.module.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: "Resources/Fonts"
        ) {
            return url
        }
        return Bundle.module.url(
            forResource: resourceName,
            withExtension: resourceExtension
        )
    }
}
