import CoreGraphics
import CoreImage
import Foundation

/// Tool-layer only: turns a rough Vision (or other) matte into SAM point/box prompts.
/// Class-agnostic sampling — callers decide which rough mask to feed in.
enum SelectionPromptBuilder {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Samples confident interior positives, exterior negatives, and a padded bounding box.
    static func fromRoughMask(
        _ mask: SelectionMask,
        imageExtent: CGRect,
        positiveCount: Int = 4,
        negativeCount: Int = 2,
        onThreshold: UInt8 = 140,
        offThreshold: UInt8 = 40
    ) -> SelectionPrompt {
        let extent = imageExtent.integral
        let maskCI = mask.ciImageMatching(extent: extent)
        let width = max(1, Int(extent.width.rounded()))
        let height = max(1, Int(extent.height.rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height)
        Self.ciContext.render(
            maskCI,
            toBitmap: &pixels,
            rowBytes: width,
            bounds: CGRect(x: extent.minX, y: extent.minY, width: CGFloat(width), height: CGFloat(height)),
            format: .L8,
            colorSpace: CGColorSpaceCreateDeviceGray()
        )

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        var onIndices: [Int] = []
        onIndices.reserveCapacity(width * height / 8)
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                let v = pixels[row + x]
                if v >= onThreshold {
                    onIndices.append(row + x)
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }

        guard !onIndices.isEmpty, maxX >= minX, maxY >= minY else {
            let center = CGPoint(x: extent.midX, y: extent.midY)
            return .point(center)
        }

        let pad = max(2, Int(min(width, height) / 64))
        let box = CGRect(
            x: extent.minX + CGFloat(max(0, minX - pad)),
            y: extent.minY + CGFloat(max(0, minY - pad)),
            width: CGFloat(min(width - 1, maxX + pad) - max(0, minX - pad) + 1),
            height: CGFloat(min(height - 1, maxY + pad) - max(0, minY - pad) + 1)
        )

        // Prefer interior samples: require a small neighborhood also on-mask.
        let radius = max(1, min(width, height) / 80)
        var interior: [CGPoint] = []
        interior.reserveCapacity(positiveCount)
        let step = max(1, onIndices.count / max(positiveCount * 4, 1))
        var i = 0
        while i < onIndices.count && interior.count < positiveCount {
            let idx = onIndices[i]
            let x = idx % width
            let y = idx / width
            if isInterior(x: x, y: y, width: width, height: height, pixels: pixels, threshold: onThreshold, radius: radius) {
                interior.append(CGPoint(x: extent.minX + CGFloat(x) + 0.5, y: extent.minY + CGFloat(y) + 0.5))
            }
            i += step
        }
        if interior.isEmpty {
            // Fallback: any on-mask samples.
            let fallbackStep = max(1, onIndices.count / max(positiveCount, 1))
            var j = 0
            while j < onIndices.count && interior.count < positiveCount {
                let idx = onIndices[j]
                let x = idx % width
                let y = idx / width
                interior.append(CGPoint(x: extent.minX + CGFloat(x) + 0.5, y: extent.minY + CGFloat(y) + 0.5))
                j += fallbackStep
            }
        }

        var negatives: [CGPoint] = []
        negatives.reserveCapacity(negativeCount)
        let candidates: [(Int, Int)] = [
            (max(0, minX - pad * 3), (minY + maxY) / 2),
            (min(width - 1, maxX + pad * 3), (minY + maxY) / 2),
            ((minX + maxX) / 2, max(0, minY - pad * 3)),
            ((minX + maxX) / 2, min(height - 1, maxY + pad * 3)),
            (0, 0),
            (width - 1, height - 1),
            (0, height - 1),
            (width - 1, 0)
        ]
        for (x, y) in candidates where negatives.count < negativeCount {
            if pixels[y * width + x] <= offThreshold {
                negatives.append(CGPoint(x: extent.minX + CGFloat(x) + 0.5, y: extent.minY + CGFloat(y) + 0.5))
            }
        }

        return SelectionPrompt(
            positivePoints: interior,
            negativePoints: negatives,
            box: box
        )
    }

    private static func isInterior(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        pixels: [UInt8],
        threshold: UInt8,
        radius: Int
    ) -> Bool {
        for dy in -radius...radius {
            for dx in -radius...radius {
                let nx = x + dx
                let ny = y + dy
                if nx < 0 || ny < 0 || nx >= width || ny >= height { return false }
                if pixels[ny * width + nx] < threshold { return false }
            }
        }
        return true
    }
}
