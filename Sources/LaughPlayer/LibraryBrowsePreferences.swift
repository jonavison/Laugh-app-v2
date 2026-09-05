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

    /// Slider stop index 0...2
    var sliderValue: Double {
        switch self {
        case .small: return 0
        case .medium: return 1
        case .large: return 2
        }
    }

    static func from(sliderValue: Double) -> LibraryBrowseGalleryScale {
        let stepped = Int(sliderValue.rounded())
        switch stepped {
        case 0: return .small
        case 1: return .medium
        default: return .large
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
    var contentInset: CGFloat

    static func metrics(
        mode: LibraryBrowseViewMode,
        galleryScale: LibraryBrowseGalleryScale
    ) -> LibraryBrowseTileMetrics {
        switch mode {
        case .gallery:
            // Square media mosaic; folder tiles share the same footprint with distinct chrome.
            switch galleryScale {
            case .small:
                return LibraryBrowseTileMetrics(
                    minItemSize: NSSize(width: 148, height: 148),
                    maxItemSize: NSSize(width: 176, height: 176),
                    interitemSpacing: 4,
                    lineSpacing: 4,
                    thumbHeight: 176,
                    folderIconPointSize: 48,
                    thumbnailMaxSide: 280,
                    showsTitle: false,
                    contentInset: 8
                )
            case .medium:
                return LibraryBrowseTileMetrics(
                    minItemSize: NSSize(width: 184, height: 184),
                    maxItemSize: NSSize(width: 220, height: 220),
                    interitemSpacing: 5,
                    lineSpacing: 5,
                    thumbHeight: 220,
                    folderIconPointSize: 56,
                    thumbnailMaxSide: 340,
                    showsTitle: false,
                    contentInset: 8
                )
            case .large:
                return LibraryBrowseTileMetrics(
                    minItemSize: NSSize(width: 220, height: 220),
                    maxItemSize: NSSize(width: 280, height: 280),
                    interitemSpacing: 6,
                    lineSpacing: 6,
                    thumbHeight: 280,
                    folderIconPointSize: 64,
                    thumbnailMaxSide: 420,
                    showsTitle: false,
                    contentInset: 8
                )
            }
        case .grid:
            return LibraryBrowseTileMetrics(
                minItemSize: NSSize(width: 160, height: 176),
                maxItemSize: NSSize(width: 196, height: 200),
                interitemSpacing: 12,
                lineSpacing: 12,
                thumbHeight: 120,
                folderIconPointSize: 52,
                thumbnailMaxSide: 260,
                showsTitle: true,
                contentInset: 14
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
                contentInset: 14
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
