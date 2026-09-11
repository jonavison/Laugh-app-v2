import AppKit
import Foundation

/// Resolves folder icons for the library sidebar and browse grid.
///
/// - **Custom** Finder icons → full-color `NSWorkspace` / effective icon
/// - **Special** home folders (Downloads, Desktop, …) → Finder-*sidebar*-style SF Symbols
///   (not the big blue Desktop folder glyph, which looks identical at 16pt)
/// - **Generic** folders → Laugh `folder` / `folder.fill` symbol
enum LibraryFolderIcon {
    /// Finder `kHasCustomIcon` bit in `com.apple.FinderInfo` flags (big-endian at offset 8).
    static let customIconFinderFlag: UInt16 = 0x0400

    /// Well-known home-folder leaf names (English + common locales).
    private static let specialHomeFolderNames: Set<String> = [
        "Downloads", "Desktop", "Documents", "Pictures", "Movies", "Music",
        "Téléchargements", "Bureau", "Images", "Films", "Musique",
        "Descargas", "Escritorio", "Documentos", "Imágenes", "Películas", "Música"
    ]

    struct ResolvedImage {
        let image: NSImage
        /// Finder custom icons are full-color; SF Symbols stay template for Laugh tinting.
        let isTemplate: Bool
        /// Optional brand/system tint for special-folder sidebar glyphs.
        let tintColor: NSColor?
    }

    /// Pure decision for tests — pass filesystem facts from the AppKit helper.
    static func prefersFinderIcon(
        directoryURL: URL,
        hasIconResourceFile: Bool,
        finderInfoFlags: UInt16?,
        specialDirectoryURLs: [URL],
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        if hasCustomIcon(
            hasIconResourceFile: hasIconResourceFile,
            finderInfoFlags: finderInfoFlags
        ) {
            return true
        }
        let standardized = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        if specialDirectoryURLs.contains(where: {
            $0.resolvingSymlinksInPath().standardizedFileURL == standardized
        }) {
            return true
        }
        return isSpecialHomeFolder(directoryURL: standardized, homeDirectoryURL: homeDirectoryURL)
    }

    static func hasCustomIcon(hasIconResourceFile: Bool, finderInfoFlags: UInt16?) -> Bool {
        if hasIconResourceFile { return true }
        if let flags = finderInfoFlags, (flags & customIconFinderFlag) != 0 { return true }
        return false
    }

    /// `Downloads` / `Desktop` / … directly under the user’s home folder.
    static func isSpecialHomeFolder(
        directoryURL: URL,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let dirPath = (directoryURL.path as NSString).standardizingPath
        let homePath = (homeDirectoryURL.path as NSString).standardizingPath
        let parentPath = (dirPath as NSString).deletingLastPathComponent
        guard parentPath == homePath else { return false }
        return specialHomeFolderNames.contains((dirPath as NSString).lastPathComponent)
    }

    /// Finder-sidebar style glyph for a special folder (never the blue Desktop folder).
    static func specialSidebarSymbol(for directoryURL: URL) -> String? {
        let name = directoryURL.lastPathComponent
        switch name {
        case "Downloads", "Téléchargements", "Descargas":
            return "arrow.down.circle.fill"
        case "Desktop", "Bureau", "Escritorio":
            return "menubar.dock.rectangle"
        case "Documents", "Documentos":
            return "doc.fill"
        case "Pictures", "Images", "Imágenes":
            return "photo.fill"
        case "Movies", "Films", "Películas":
            return "film.fill"
        case "Music", "Musique", "Música":
            return "music.note"
        default:
            return nil
        }
    }

    /// Reads Finder flags from a 32-byte `com.apple.FinderInfo` blob.
    static func finderInfoFlags(fromFinderInfo data: Data) -> UInt16? {
        guard data.count >= 10 else { return nil }
        return (UInt16(data[8]) << 8) | UInt16(data[9])
    }

    /// Sidebar / grid helper.
    /// - Parameter forceFinderAppearance: Sidebar roots prefer special glyphs / custom icons.
    static func resolve(
        for directoryURL: URL,
        pointSize: CGFloat,
        symbolFallback: String = "folder.fill",
        forceFinderAppearance: Bool = false
    ) -> ResolvedImage {
        let custom = hasCustomIcon(
            hasIconResourceFile: hasIconResourceFile(at: directoryURL),
            finderInfoFlags: readFinderInfoFlags(at: directoryURL)
        )
        if custom {
            return ResolvedImage(
                image: rasterizedFinderIcon(for: directoryURL, pointSize: pointSize),
                isTemplate: false,
                tintColor: nil
            )
        }

        let isSpecial = isSpecialDirectory(directoryURL)
        if forceFinderAppearance || isSpecial, let symbolName = specialSidebarSymbol(for: directoryURL) {
            if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
                let configured = symbol.withSymbolConfiguration(config) ?? symbol
                configured.isTemplate = true
                return ResolvedImage(image: configured, isTemplate: true, tintColor: nil)
            }
        }

        if let symbol = NSImage(systemSymbolName: symbolFallback, accessibilityDescription: "Folder") {
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            let configured = symbol.withSymbolConfiguration(config) ?? symbol
            configured.isTemplate = true
            return ResolvedImage(image: configured, isTemplate: true, tintColor: nil)
        }

        return ResolvedImage(
            image: rasterizedFinderIcon(for: directoryURL, pointSize: pointSize),
            isTemplate: false,
            tintColor: nil
        )
    }

    static func prefersFinderIcon(for directoryURL: URL) -> Bool {
        prefersFinderIcon(
            directoryURL: directoryURL,
            hasIconResourceFile: hasIconResourceFile(at: directoryURL),
            finderInfoFlags: readFinderInfoFlags(at: directoryURL),
            specialDirectoryURLs: specialUserDirectoryURLs()
        )
    }

    static func isSpecialDirectory(_ directoryURL: URL) -> Bool {
        let standardized = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        if specialUserDirectoryURLs().contains(where: {
            $0.resolvingSymlinksInPath().standardizedFileURL == standardized
        }) {
            return true
        }
        return isSpecialHomeFolder(directoryURL: standardized)
    }

    /// High-quality custom Finder icon scaled for sidebar / grid chrome.
    static func rasterizedFinderIcon(for directoryURL: URL, pointSize: CGFloat) -> NSImage {
        let source = workspaceIcon(for: directoryURL)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let pixels = max(1, Int(ceil(pointSize * scale)))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            let copy = source.copy() as? NSImage ?? source
            copy.size = NSSize(width: pointSize, height: pointSize)
            copy.isTemplate = false
            return copy
        }

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current?.imageInterpolation = .high
        let drawRect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        NSColor.clear.setFill()
        drawRect.fill()
        let hintRect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        if let rep = source.bestRepresentation(for: hintRect, context: nil, hints: [
            .interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)
        ]) {
            rep.draw(in: drawRect)
        } else {
            source.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.current = previous

        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        image.addRepresentation(bitmap)
        image.isTemplate = false
        return image
    }

    private static func workspaceIcon(for directoryURL: URL) -> NSImage {
        if let values = try? directoryURL.resourceValues(forKeys: [.effectiveIconKey]),
           let icon = values.effectiveIcon as? NSImage {
            return icon
        }
        return NSWorkspace.shared.icon(forFile: directoryURL.path)
    }

    private static func hasIconResourceFile(at directoryURL: URL) -> Bool {
        let iconURL = directoryURL.appendingPathComponent("Icon\r")
        return FileManager.default.fileExists(atPath: iconURL.path)
    }

    private static func readFinderInfoFlags(at directoryURL: URL) -> UInt16? {
        var buffer = [UInt8](repeating: 0, count: 32)
        let result = buffer.withUnsafeMutableBytes { raw in
            getxattr(
                directoryURL.path,
                "com.apple.FinderInfo",
                raw.baseAddress,
                32,
                0,
                0
            )
        }
        guard result >= 10 else { return nil }
        return finderInfoFlags(fromFinderInfo: Data(buffer))
    }

    private static func specialUserDirectoryURLs() -> [URL] {
        let keys: [FileManager.SearchPathDirectory] = [
            .downloadsDirectory,
            .desktopDirectory,
            .documentDirectory,
            .picturesDirectory,
            .moviesDirectory,
            .musicDirectory
        ]
        return keys.compactMap {
            FileManager.default.urls(for: $0, in: .userDomainMask).first
        }
    }
}
