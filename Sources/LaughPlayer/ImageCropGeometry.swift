import CoreGraphics
import Foundation

/// Aspect lock for image crop mode.
enum ImageCropAspect: Int, CaseIterable, Hashable {
    case free
    case original

    // Classic
    case square
    case portrait4x5
    case landscape5x4
    case landscape3x2
    case portrait2x3
    case landscape4x3
    case portrait3x4
    case landscape16x9
    case portrait9x16
    case landscape21x9

    // Social
    case instagramFeed
    case instagramSquare
    case instagramStory
    case facebookCover
    case facebookPost
    case twitterHeader
    case youtubeThumbnail
    case pinterestPin
    case linkedInCover

    // Product
    case productSquare
    case productPortrait

    /// Unlocked freeform crop (menu footer).
    case custom

    /// Menu row title, e.g. `Instagram Feed (4:5)`.
    var title: String {
        switch self {
        case .free: return "Free"
        case .original: return "Original"
        case .square: return "Square (1:1)"
        case .portrait4x5: return "4:5"
        case .landscape5x4: return "5:4"
        case .landscape3x2: return "3:2"
        case .portrait2x3: return "2:3"
        case .landscape4x3: return "4:3"
        case .portrait3x4: return "3:4"
        case .landscape16x9: return "16:9"
        case .portrait9x16: return "9:16"
        case .landscape21x9: return "21:9"
        case .instagramFeed: return "Instagram Feed (4:5)"
        case .instagramSquare: return "Instagram Square (1:1)"
        case .instagramStory: return "Instagram Story (9:16)"
        case .facebookCover: return "Facebook Cover (2.63:1)"
        case .facebookPost: return "Facebook Post (1.91:1)"
        case .twitterHeader: return "X / Twitter Header (3:1)"
        case .youtubeThumbnail: return "YouTube Thumbnail (16:9)"
        case .pinterestPin: return "Pinterest Pin (2:3)"
        case .linkedInCover: return "LinkedIn Cover (4:1)"
        case .productSquare: return "Product Square (1:1)"
        case .productPortrait: return "Product Portrait (4:5)"
        case .custom: return "Custom"
        }
    }

    /// Compact label for the closed popup.
    var compactTitle: String {
        switch self {
        case .free: return "Free"
        case .original: return "Original"
        case .square: return "1:1"
        case .portrait4x5: return "4:5"
        case .landscape5x4: return "5:4"
        case .landscape3x2: return "3:2"
        case .portrait2x3: return "2:3"
        case .landscape4x3: return "4:3"
        case .portrait3x4: return "3:4"
        case .landscape16x9: return "16:9"
        case .portrait9x16: return "9:16"
        case .landscape21x9: return "21:9"
        case .instagramFeed: return "IG Feed"
        case .instagramSquare: return "IG Square"
        case .instagramStory: return "IG Story"
        case .facebookCover: return "FB Cover"
        case .facebookPost: return "FB Post"
        case .twitterHeader: return "X Header"
        case .youtubeThumbnail: return "YT Thumb"
        case .pinterestPin: return "Pinterest"
        case .linkedInCover: return "LI Cover"
        case .productSquare: return "Product 1:1"
        case .productPortrait: return "Product 4:5"
        case .custom: return "Custom"
        }
    }

    /// Width / height when locked. `nil` for free/custom. `original` uses the image’s own ratio.
    func lockedRatio(imageSize: CGSize) -> CGFloat? {
        switch self {
        case .free, .custom:
            return nil
        case .original:
            guard imageSize.height > 0.5 else { return nil }
            return imageSize.width / imageSize.height
        case .square, .instagramSquare, .productSquare:
            return 1
        case .portrait4x5, .instagramFeed, .productPortrait:
            return 4.0 / 5.0
        case .landscape5x4:
            return 5.0 / 4.0
        case .landscape3x2:
            return 3.0 / 2.0
        case .portrait2x3, .pinterestPin:
            return 2.0 / 3.0
        case .landscape4x3:
            return 4.0 / 3.0
        case .portrait3x4:
            return 3.0 / 4.0
        case .landscape16x9, .youtubeThumbnail:
            return 16.0 / 9.0
        case .portrait9x16, .instagramStory:
            return 9.0 / 16.0
        case .landscape21x9:
            return 21.0 / 9.0
        case .facebookCover:
            return 820.0 / 312.0
        case .facebookPost:
            return 1.91
        case .twitterHeader:
            return 3.0
        case .linkedInCover:
            return 4.0
        }
    }

    /// Ordered menu sections for the crop aspect popup.
    static var menuSections: [(header: String?, items: [ImageCropAspect])] {
        [
            (nil, [.free, .original]),
            ("Classic", [
                .square, .portrait4x5, .landscape5x4,
                .landscape3x2, .portrait2x3,
                .landscape4x3, .portrait3x4,
                .landscape16x9, .portrait9x16, .landscape21x9
            ]),
            ("Social", [
                .instagramFeed, .instagramSquare, .instagramStory,
                .facebookCover, .facebookPost,
                .twitterHeader, .youtubeThumbnail,
                .pinterestPin, .linkedInCover
            ]),
            ("Product", [.productSquare, .productPortrait]),
            (nil, [.custom])
        ]
    }
}

/// Normalized crop in **post-rotation** pixel space.
/// Origin is bottom-leading (Core Image / Quartz), unit square is the full oriented image.
enum ImageCropGeometry {
    static let fullNormalized = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// Minimum edge length in normalized units.
    static let minNormalizedEdge: CGFloat = 0.05
    /// Free straighten while cropping (degrees).
    static let maxStraightenDegrees: CGFloat = 45

    static func clampStraightenRadians(_ radians: CGFloat) -> CGFloat {
        let maxR = maxStraightenDegrees * .pi / 180
        return min(max(radians, -maxR), maxR)
    }

    static func straightenDegrees(from radians: CGFloat) -> CGFloat {
        radians * 180 / .pi
    }

    static func isIdentityStraighten(_ radians: CGFloat) -> Bool {
        abs(radians) < 0.0005
    }

    static func isIdentity(_ rect: CGRect?) -> Bool {
        guard let rect else { return true }
        return rect.integralNearlyEqual(fullNormalized)
    }

    /// Clamp into the unit square and enforce a minimum size.
    /// The unit square **is** the image — crop must never extend outside.
    static func sanitized(_ rect: CGRect) -> CGRect {
        var r = rect.standardized
        if r.width < minNormalizedEdge { r.size.width = minNormalizedEdge }
        if r.height < minNormalizedEdge { r.size.height = minNormalizedEdge }
        if r.width > 1 { r.size.width = 1 }
        if r.height > 1 { r.size.height = 1 }
        r.origin.x = min(max(r.origin.x, 0), 1 - r.width)
        r.origin.y = min(max(r.origin.y, 0), 1 - r.height)
        // Final hard clamp against float drift.
        r.origin.x = min(max(r.origin.x, 0), 1)
        r.origin.y = min(max(r.origin.y, 0), 1)
        r.size.width = min(max(r.size.width, minNormalizedEdge), 1 - r.origin.x)
        r.size.height = min(max(r.size.height, minNormalizedEdge), 1 - r.origin.y)
        return r
    }

    /// Pixel size of the oriented image **before** straighten expands the AABB.
    static func preStraightenSize(natural: CGSize, quarterTurns: Int) -> CGSize {
        let turns = ((quarterTurns % 4) + 4) % 4
        if turns % 2 != 0 {
            return CGSize(width: natural.height, height: natural.width)
        }
        return natural
    }

    /// Keep an AABB-normalized crop inside opaque photo pixels after straighten
    /// (empty corners of the straightened bitmap are outside the image).
    static func clampToOpaqueContent(
        _ rect: CGRect,
        straightenRadians: CGFloat,
        preStraightenSize: CGSize
    ) -> CGRect {
        var r = sanitized(rect)
        let angle = clampStraightenRadians(straightenRadians)
        guard !isIdentityStraighten(angle) else { return r }
        guard preStraightenSize.width > 1, preStraightenSize.height > 1 else { return r }
        if opaqueContentContains(r, radians: angle, preSize: preStraightenSize) {
            return r
        }

        // Prefer translating (keeps size) before shrinking — matches drag-to-edge UX.
        let target = CGPoint(x: 0.5, y: 0.5)
        for _ in 0..<32 {
            if opaqueContentContains(r, radians: angle, preSize: preStraightenSize) {
                return sanitized(r)
            }
            let dx = (target.x - r.midX) * 0.18
            let dy = (target.y - r.midY) * 0.18
            if abs(dx) < 0.0001, abs(dy) < 0.0001 { break }
            r = sanitized(r.offsetBy(dx: dx, dy: dy))
        }
        if opaqueContentContains(r, radians: angle, preSize: preStraightenSize) {
            return r
        }

        // Shrink toward center until all four corners sit on opaque pixels.
        let cx = r.midX
        let cy = r.midY
        var lo: CGFloat = 0
        var hi: CGFloat = 1
        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            let cand = sanitized(
                CGRect(
                    x: cx - r.width * mid / 2,
                    y: cy - r.height * mid / 2,
                    width: r.width * mid,
                    height: r.height * mid
                )
            )
            if opaqueContentContains(cand, radians: angle, preSize: preStraightenSize) {
                lo = mid
            } else {
                hi = mid
            }
        }
        let scale = max(lo, 0.02)
        return sanitized(
            CGRect(
                x: cx - r.width * scale / 2,
                y: cy - r.height * scale / 2,
                width: r.width * scale,
                height: r.height * scale
            )
        )
    }

    static func opaqueContentContains(
        _ rect: CGRect,
        radians: CGFloat,
        preSize: CGSize
    ) -> Bool {
        let r = rect.standardized
        let corners = [
            CGPoint(x: r.minX, y: r.minY),
            CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.maxY),
            CGPoint(x: r.maxX, y: r.maxY)
        ]
        return corners.allSatisfy { pointInOpaqueContent($0, radians: radians, preSize: preSize) }
    }

    /// `p` is normalized in the post-straighten AABB (unit square).
    static func pointInOpaqueContent(
        _ p: CGPoint,
        radians: CGFloat,
        preSize: CGSize
    ) -> Bool {
        let c = cos(radians)
        let s = sin(radians)
        let outW = preSize.width * abs(c) + preSize.height * abs(s)
        let outH = preSize.width * abs(s) + preSize.height * abs(c)
        guard outW > 1, outH > 1 else { return true }
        let x = (p.x - 0.5) * outW
        let y = (p.y - 0.5) * outH
        // Inverse of CGAffineTransform rotation by `radians` (CCW).
        let localX = x * c + y * s
        let localY = -x * s + y * c
        let eps: CGFloat = 1.0
        return abs(localX) <= preSize.width / 2 + eps
            && abs(localY) <= preSize.height / 2 + eps
    }

    /// Pixel crop rect in the oriented image’s CI extent (origin bottom-leading).
    static func pixelRect(normalized: CGRect, imageSize: CGSize) -> CGRect {
        let n = sanitized(normalized)
        return CGRect(
            x: n.origin.x * imageSize.width,
            y: n.origin.y * imageSize.height,
            width: n.size.width * imageSize.width,
            height: n.size.height * imageSize.height
        ).integral
    }

    /// Default crop: largest rect of `aspect` centered in the image (or full frame for free).
    static func defaultNormalizedRect(aspect: ImageCropAspect, imageSize: CGSize) -> CGRect {
        guard let ratio = aspect.lockedRatio(imageSize: imageSize) else {
            return fullNormalized
        }
        return largestCenteredRect(aspectRatio: ratio)
    }

    static func largestCenteredRect(aspectRatio: CGFloat) -> CGRect {
        guard aspectRatio > 0.001 else { return fullNormalized }
        // Unit square; fit ratio.
        if aspectRatio >= 1 {
            let height = 1 / aspectRatio
            return sanitized(CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height))
        } else {
            let width = aspectRatio
            return sanitized(CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1))
        }
    }

    /// Resize `rect` from `handle` so the result matches `aspectRatio` when non-nil.
    /// Coordinates are normalized (bottom-leading).
    static func resize(
        rect: CGRect,
        handle: ImageCropHandle,
        to point: CGPoint,
        aspectRatio: CGFloat?
    ) -> CGRect {
        var r = rect.standardized
        let p = CGPoint(x: min(max(point.x, 0), 1), y: min(max(point.y, 0), 1))

        if let ratio = aspectRatio, ratio > 0.001 {
            return resizeLocked(rect: r, handle: handle, to: p, aspectRatio: ratio)
        }

        switch handle {
        case .move:
            let dx = p.x - r.midX
            let dy = p.y - r.midY
            r.origin.x += dx
            r.origin.y += dy
            r.origin.x = min(max(r.origin.x, 0), 1 - r.width)
            r.origin.y = min(max(r.origin.y, 0), 1 - r.height)
            return sanitized(r)
        case .minX:
            let maxX = r.maxX
            r.origin.x = min(p.x, maxX - minNormalizedEdge)
            r.size.width = maxX - r.origin.x
        case .maxX:
            r.size.width = max(p.x - r.minX, minNormalizedEdge)
        case .minY:
            let maxY = r.maxY
            r.origin.y = min(p.y, maxY - minNormalizedEdge)
            r.size.height = maxY - r.origin.y
        case .maxY:
            r.size.height = max(p.y - r.minY, minNormalizedEdge)
        case .minXMinY:
            let maxX = r.maxX
            let maxY = r.maxY
            r.origin.x = min(p.x, maxX - minNormalizedEdge)
            r.origin.y = min(p.y, maxY - minNormalizedEdge)
            r.size.width = maxX - r.origin.x
            r.size.height = maxY - r.origin.y
        case .maxXMinY:
            let maxY = r.maxY
            r.size.width = max(p.x - r.minX, minNormalizedEdge)
            r.origin.y = min(p.y, maxY - minNormalizedEdge)
            r.size.height = maxY - r.origin.y
        case .minXMaxY:
            let maxX = r.maxX
            r.origin.x = min(p.x, maxX - minNormalizedEdge)
            r.size.width = maxX - r.origin.x
            r.size.height = max(p.y - r.minY, minNormalizedEdge)
        case .maxXMaxY:
            r.size.width = max(p.x - r.minX, minNormalizedEdge)
            r.size.height = max(p.y - r.minY, minNormalizedEdge)
        }
        return sanitized(r)
    }

    /// Snap to the largest centered frame for a locked aspect (correct social/output size).
    /// Free / Custom keep the current rect.
    static func applyAspect(_ aspect: ImageCropAspect, to rect: CGRect, imageSize: CGSize) -> CGRect {
        guard aspect.lockedRatio(imageSize: imageSize) != nil else {
            return sanitized(rect)
        }
        return defaultNormalizedRect(aspect: aspect, imageSize: imageSize)
    }

    private static func resizeLocked(
        rect: CGRect,
        handle: ImageCropHandle,
        to point: CGPoint,
        aspectRatio ratio: CGFloat
    ) -> CGRect {
        let r = rect.standardized
        switch handle {
        case .move:
            return resize(rect: r, handle: .move, to: point, aspectRatio: nil)
        case .maxXMaxY, .maxX, .maxY:
            let anchor = CGPoint(x: r.minX, y: r.minY)
            return lockedFromAnchor(anchor: anchor, growingCorner: point, ratio: ratio, preferMax: true)
        case .minXMinY, .minX, .minY:
            let anchor = CGPoint(x: r.maxX, y: r.maxY)
            return lockedFromAnchor(anchor: anchor, growingCorner: point, ratio: ratio, preferMax: false)
        case .maxXMinY:
            let anchor = CGPoint(x: r.minX, y: r.maxY)
            return lockedCorner(anchor: anchor, point: point, ratio: ratio, flipY: true)
        case .minXMaxY:
            let anchor = CGPoint(x: r.maxX, y: r.minY)
            return lockedCorner(anchor: anchor, point: point, ratio: ratio, flipX: true)
        }
    }

    private static func lockedFromAnchor(
        anchor: CGPoint,
        growingCorner: CGPoint,
        ratio: CGFloat,
        preferMax: Bool
    ) -> CGRect {
        _ = preferMax
        let p = CGPoint(
            x: min(max(growingCorner.x, 0), 1),
            y: min(max(growingCorner.y, 0), 1)
        )
        let dirX: CGFloat = p.x >= anchor.x ? 1 : -1
        let dirY: CGFloat = p.y >= anchor.y ? 1 : -1
        let maxW = max(dirX > 0 ? (1 - anchor.x) : anchor.x, minNormalizedEdge)
        let maxH = max(dirY > 0 ? (1 - anchor.y) : anchor.y, minNormalizedEdge)

        var width = abs(p.x - anchor.x)
        var height = abs(p.y - anchor.y)
        if width / max(height, 0.0001) > ratio {
            height = width / ratio
        } else {
            width = height * ratio
        }
        width = max(width, minNormalizedEdge)
        height = max(height, minNormalizedEdge)

        if width > maxW {
            width = maxW
            height = width / ratio
        }
        if height > maxH {
            height = maxH
            width = height * ratio
        }
        width = min(max(width, minNormalizedEdge), maxW)
        height = min(max(height, minNormalizedEdge), maxH)
        // Reconcile ratio after both clamps.
        if width / max(height, 0.0001) > ratio {
            height = width / ratio
            if height > maxH {
                height = maxH
                width = height * ratio
            }
        } else {
            width = height * ratio
            if width > maxW {
                width = maxW
                height = width / ratio
            }
        }

        let originX = dirX > 0 ? anchor.x : anchor.x - width
        let originY = dirY > 0 ? anchor.y : anchor.y - height
        return sanitized(CGRect(x: originX, y: originY, width: width, height: height))
    }

    private static func lockedCorner(
        anchor: CGPoint,
        point: CGPoint,
        ratio: CGFloat,
        flipX: Bool = false,
        flipY: Bool = false
    ) -> CGRect {
        let dirX: CGFloat = flipX ? (point.x <= anchor.x ? -1 : 1) : (point.x >= anchor.x ? 1 : -1)
        let dirY: CGFloat = flipY ? (point.y <= anchor.y ? -1 : 1) : (point.y >= anchor.y ? 1 : -1)
        _ = dirX
        _ = dirY
        return lockedFromAnchor(
            anchor: anchor,
            growingCorner: point,
            ratio: ratio,
            preferMax: true
        )
    }
}

enum ImageCropHandle: Hashable {
    case move
    case minX
    case maxX
    case minY
    case maxY
    case minXMinY
    case maxXMinY
    case minXMaxY
    case maxXMaxY
}

private extension CGRect {
    func integralNearlyEqual(_ other: CGRect, epsilon: CGFloat = 0.002) -> Bool {
        abs(minX - other.minX) < epsilon
            && abs(minY - other.minY) < epsilon
            && abs(width - other.width) < epsilon
            && abs(height - other.height) < epsilon
    }
}
