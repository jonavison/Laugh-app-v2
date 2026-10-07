import AppKit
import Foundation

enum LibraryBrowseViewMode: String, CaseIterable {
    case gallery
    case grid
    case list

    var menuTitle: String {
        switch self {
        case .gallery: return "Gallery"
        case .grid: return "Grid"
        case .list: return "List"
        }
    }

    var symbolName: String {
        switch self {
        case .gallery: return "rectangle.grid.2x2"
        case .grid: return "square.grid.3x3"
        case .list: return "list.bullet"
        }
    }

    var isCollectionLayout: Bool {
        switch self {
        case .gallery, .grid: return true
        case .list: return false
        }
    }

    var isListLayout: Bool {
        !isCollectionLayout
    }
}

enum LibraryBrowseGalleryScale: String, CaseIterable {
    case small
    case medium
    case large
    case xlarge
    case xxlarge

    /// Slider stop index 0...4
    var sliderValue: Double {
        switch self {
        case .small: return 0
        case .medium: return 1
        case .large: return 2
        case .xlarge: return 3
        case .xxlarge: return 4
        }
    }

    static func from(sliderValue: Double) -> LibraryBrowseGalleryScale {
        let stepped = Int(sliderValue.rounded())
        switch stepped {
        case 0: return .small
        case 1: return .medium
        case 2: return .large
        case 3: return .xlarge
        default: return .xxlarge
        }
    }
}

enum LibraryKindFilter: String, CaseIterable {
    case all
    case videos
    case images
    case folders

    var title: String {
        switch self {
        case .all: return "All"
        case .videos: return "Videos"
        case .images: return "Images"
        case .folders: return "Folders"
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .videos: return "film"
        case .images: return "photo"
        case .folders: return "folder"
        }
    }
}

/// Layout metrics for Gallery / Grid collection cells.
struct LibraryBrowseTileMetrics: Equatable {
    var minItemSize: NSSize
    var maxItemSize: NSSize
    var interitemSpacing: CGFloat
    var lineSpacing: CGFloat
    var thumbHeight: CGFloat
    var folderIconPointSize: CGFloat
    var thumbnailMaxSide: CGFloat
    /// When false, tiles are image-only (Gallery) — no caption under the preview.
    var showsTitle: Bool
    /// Left / right / bottom inset inside the scroll document.
    var contentInset: CGFloat
    /// Extra breathing room under the toolbar before the first row.
    var contentTopInset: CGFloat

    static func metrics(
        mode: LibraryBrowseViewMode,
        galleryScale: LibraryBrowseGalleryScale
    ) -> LibraryBrowseTileMetrics {
        switch mode {
        case .gallery:
            // Landscape mosaic (~16:9) — images full-bleed; folders sit smaller inside the cell.
            switch galleryScale {
            case .small:
                return LibraryBrowseTileMetrics(
                    minItemSize: NSSize(width: 200, height: 112),
                    maxItemSize: NSSize(width: 240, height: 135),
                    interitemSpacing: 4,
                    lineSpacing: 4,
                    thumbHeight: 135,
                    folderIconPointSize: 40,
                    thumbnailMaxSide: 360,
                    showsTitle: false,
                    contentInset: 10,
                    contentTopInset: 20
                )
            case .medium:
                return LibraryBrowseTileMetrics(
                    minItemSize: NSSize(width: 268, height: 151),
                    maxItemSize: NSSize(width: 320, height: 180),
                    interitemSpacing: 5,
                    lineSpacing: 5,
                    thumbHeight: 180,
                    folderIconPointSize: 46,
                    thumbnailMaxSide: 480,
                    showsTitle: false,
                    contentInset: 10,
                    contentTopInset: 22
                )
            case .large:
                return LibraryBrowseTileMetrics(
                    minItemSize: NSSize(width: 380, height: 214),
                    maxItemSize: NSSize(width: 460, height: 259),
                    interitemSpacing: 6,
                    lineSpacing: 6,
                    thumbHeight: 259,
                    folderIconPointSize: 54,
                    thumbnailMaxSide: 720,
                    showsTitle: false,
                    contentInset: 12,
                    contentTopInset: 24
                )
            case .xlarge:
                return LibraryBrowseTileMetrics(
                    minItemSize: NSSize(width: 520, height: 292),
                    maxItemSize: NSSize(width: 640, height: 360),
                    interitemSpacing: 8,
                    lineSpacing: 8,
                    thumbHeight: 360,
                    folderIconPointSize: 60,
                    thumbnailMaxSide: 960,
                    showsTitle: false,
                    contentInset: 14,
                    contentTopInset: 24
                )
            case .xxlarge:
                return LibraryBrowseTileMetrics(
                    minItemSize: NSSize(width: 680, height: 382),
                    maxItemSize: NSSize(width: 880, height: 495),
                    interitemSpacing: 10,
                    lineSpacing: 10,
                    thumbHeight: 495,
                    folderIconPointSize: 68,
                    thumbnailMaxSide: 1280,
                    showsTitle: false,
                    contentInset: 16,
                    contentTopInset: 26
                )
            }
        case .grid:
            // Fixed size: GridLayout otherwise pairs narrow width with max height.
            // Caption py matches Gallery (nameTop/metaBottom 6).
            // Insets must match LibraryGridCardLayout in LibraryPanelView.
            let previewInset: CGFloat = 6
            let previewTop: CGFloat = 6
            let nameTop: CGFloat = 6
            let nameMetaSpacing: CGFloat = 2
            let metaBottom: CGFloat = 6
            let nameLine: CGFloat = 15
            let metaLine: CGFloat = 13
            let width: CGFloat = 172
            let previewSide = width - previewInset * 2
            let height = previewTop + previewSide + nameTop + nameLine + nameMetaSpacing + metaLine + metaBottom
            return LibraryBrowseTileMetrics(
                minItemSize: NSSize(width: width, height: height),
                maxItemSize: NSSize(width: width, height: height),
                interitemSpacing: 12,
                lineSpacing: 12,
                thumbHeight: previewSide,
                folderIconPointSize: 48,
                thumbnailMaxSide: 320,
                showsTitle: true,
                contentInset: 16,
                contentTopInset: 24
            )
        case .list:
            return LibraryBrowseTileMetrics(
                minItemSize: NSSize(width: 120, height: 124),
                maxItemSize: NSSize(width: 160, height: 140),
                interitemSpacing: 8,
                lineSpacing: 10,
                thumbHeight: 84,
                folderIconPointSize: 46,
                thumbnailMaxSide: 200,
                showsTitle: true,
                contentInset: 16,
                contentTopInset: 20
            )
        }
    }
}

enum LibraryBrowsePreferences {
    private static let viewModeKey = "LibraryBrowseViewMode"
    private static let galleryScaleKey = "LibraryBrowseGalleryScale"
    private static let migratedKey = "LibraryBrowseViewModeMigratedV2"

    static var viewMode: LibraryBrowseViewMode {
        get {
            migrateLegacyViewModeIfNeeded()
            let raw = UserDefaults.standard.string(forKey: viewModeKey) ?? LibraryBrowseViewMode.gallery.rawValue
            if raw == "compactList" {
                UserDefaults.standard.set(LibraryBrowseViewMode.list.rawValue, forKey: viewModeKey)
                return .list
            }
            return LibraryBrowseViewMode(rawValue: raw) ?? .gallery
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: viewModeKey)
        }
    }

    static var galleryScale: LibraryBrowseGalleryScale {
        get {
            let raw = UserDefaults.standard.string(forKey: galleryScaleKey) ?? LibraryBrowseGalleryScale.large.rawValue
            return LibraryBrowseGalleryScale(rawValue: raw) ?? .large
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: galleryScaleKey)
        }
    }

    /// Old `grid` → Gallery (bigger default); `list` stays list.
    private static func migrateLegacyViewModeIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migratedKey) else { return }
        if let raw = defaults.string(forKey: viewModeKey) {
            if raw == "grid" {
                defaults.set(LibraryBrowseViewMode.gallery.rawValue, forKey: viewModeKey)
            }
            // "list" remains valid
        }
        defaults.set(true, forKey: migratedKey)
    }
}
