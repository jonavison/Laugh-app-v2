import Foundation

/// Named looks for the Presets tab (recipes over `ImageAdjustParameters` only).
enum ImageAdjustPreset: CaseIterable {
    case original
    case vivid
    case soft
    case warm
    case cool
    case contrast
    case dramatic
    case fade
    case mono
    case highKey
    case superContrast
    case portra
    case fuji
    case noir

    var title: String {
        switch self {
        case .original: return "Original"
        case .vivid: return "Vivid"
        case .soft: return "Soft"
        case .warm: return "Warm"
        case .cool: return "Cool"
        case .contrast: return "Contrast"
        case .dramatic: return "Dramatic"
        case .fade: return "Fade"
        case .mono: return "Mono"
        case .highKey: return "High Key"
        case .superContrast: return "Super Contrast"
        case .portra: return "Portra"
        case .fuji: return "Fuji"
        case .noir: return "Noir"
        }
    }

    var symbolName: String {
        switch self {
        case .original: return "circle"
        case .vivid: return "sparkles"
        case .soft: return "cloud"
        case .warm: return "sun.max"
        case .cool: return "snowflake"
        case .contrast: return "circle.lefthalf.filled"
        case .dramatic: return "moon.stars"
        case .fade: return "drop"
        case .mono: return "circle.grid.2x2"
        case .highKey: return "sun.horizon"
        case .superContrast: return "circle.righthalf.filled"
        case .portra: return "camera.filters"
        case .fuji: return "leaf"
        case .noir: return "theatermasks"
        }
    }

    var parameters: ImageAdjustParameters {
        switch self {
        case .original:
            return .identity
        case .vivid:
            return ImageAdjustParameters(
                exposure: 0.08, brightness: 0.02, contrast: 1.12, highlights: 0.92, shadows: 0.08,
                saturation: 1.28, vibrance: 0.35, temperature: 0.05,
                sharpness: 0.35, definition: 0.15, structure: 0.1
            )
        case .soft:
            return ImageAdjustParameters(
                exposure: 0.12, brightness: 0.06, contrast: 0.88, highlights: 0.78, shadows: 0.18,
                saturation: 0.92, vibrance: 0.1, temperature: 0.08, tint: 0.02,
                definition: -0.2, denoise: 0.15
            )
        case .warm:
            return ImageAdjustParameters(
                exposure: 0.05, brightness: 0.03, contrast: 1.05, highlights: 0.9, shadows: 0.1,
                saturation: 1.1, vibrance: 0.2, temperature: 0.42, tint: 0.08,
                sharpness: 0.15, definition: 0.05
            )
        case .cool:
            return ImageAdjustParameters(
                exposure: 0.02, contrast: 1.08, highlights: 0.95, shadows: 0.05,
                saturation: 1.05, vibrance: 0.15, temperature: -0.4, tint: -0.05,
                sharpness: 0.2, definition: 0.1
            )
        case .contrast:
            return ImageAdjustParameters(
                brightness: -0.02, contrast: 1.35, highlights: 0.85, shadows: -0.15,
                whites: 0.12, blacks: -0.1,
                saturation: 1.05, vibrance: 0.1,
                sharpness: 0.45, definition: 0.25, structure: 0.2
            )
        case .dramatic:
            return ImageAdjustParameters(
                exposure: -0.12, brightness: -0.05, contrast: 1.4, highlights: 0.7, shadows: -0.28,
                whites: 0.08, blacks: -0.18,
                saturation: 0.95, vibrance: 0.2, temperature: -0.08, tint: 0.04,
                sharpness: 0.55, definition: 0.35, structure: 0.3, vignette: 0.35
            )
        case .fade:
            return ImageAdjustParameters(
                exposure: 0.18, brightness: 0.1, contrast: 0.82, highlights: 0.7, shadows: 0.22,
                blacks: 0.15,
                saturation: 0.78, vibrance: -0.1, temperature: 0.12, tint: 0.06,
                splitHighlight: 0.25, splitShadow: -0.15, splitAmount: 0.35,
                definition: -0.15
            )
        case .mono:
            return ImageAdjustParameters(
                exposure: 0.05, brightness: 0.02, contrast: 1.18, highlights: 0.88, shadows: 0.12,
                blackAndWhite: 1, sharpness: 0.3, definition: 0.2, structure: 0.1
            )
        case .highKey:
            return ImageAdjustParameters(
                exposure: 0.45, brightness: 0.12, contrast: 0.92, highlights: 0.72, shadows: 0.35,
                whites: 0.28, blacks: 0.12,
                saturation: 0.88, vibrance: 0.05, temperature: 0.06,
                denoise: 0.1
            )
        case .superContrast:
            return ImageAdjustParameters(
                exposure: -0.05, contrast: 1.55, highlights: 0.78, shadows: -0.22,
                whites: 0.2, blacks: -0.25,
                saturation: 1.08, vibrance: 0.15,
                sharpness: 0.5, definition: 0.4, structure: 0.45, vignette: 0.2
            )
        case .portra:
            return ImageAdjustParameters(
                exposure: 0.06, contrast: 1.06, highlights: 0.9, shadows: 0.08,
                saturation: 1.05, vibrance: 0.18, temperature: 0.22, tint: 0.06,
                splitHighlight: 0.35, splitShadow: -0.1, splitAmount: 0.28,
                sharpness: 0.12
            )
        case .fuji:
            return ImageAdjustParameters(
                exposure: 0.04, contrast: 1.14, highlights: 0.88, shadows: -0.05,
                saturation: 1.18, vibrance: 0.22, hue: 0.04, temperature: -0.05, tint: 0.04,
                sharpness: 0.25, definition: 0.15, structure: 0.12
            )
        case .noir:
            return ImageAdjustParameters(
                exposure: -0.08, contrast: 1.45, highlights: 0.75, shadows: -0.2,
                blacks: -0.15, blackAndWhite: 1,
                sharpness: 0.4, definition: 0.25, structure: 0.2, vignette: 0.45
            )
        }
    }
}
