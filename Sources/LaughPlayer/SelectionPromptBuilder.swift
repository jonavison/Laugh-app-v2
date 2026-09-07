import CoreGraphics
import CoreImage
import Foundation

/// Tool-layer only: turns a rough Vision (or other) matte into SAM point/box prompts.
/// Class-agnostic sampling — callers decide which rough mask to feed in.
enum SelectionPromptBuilder {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Samples confident interior positives, exterior negatives, and a padded bounding box.
    ///
    /// `exclusion` is anything that is background *for this subject specifically* — in a
    /// group shot, the other people. Their pixels become negative points, which is the only
    /// signal stopping a box that overlaps a neighbour from swallowing them.
    static func fromRoughMask(
        _ mask: SelectionMask,
        imageExtent: CGRect,
        exclusion: SelectionMask? = nil,
        positiveCount: Int = 4,
        negativeCount: Int = 8,
        onThreshold: UInt8 = 140,
        offThreshold: UInt8 = 40
    ) -> SelectionPrompt {
        let extent = imageExtent.integral
        let width = max(1, Int(extent.width.rounded()))
        let height = max(1, Int(extent.height.rounded()))
        let pixels = raster(mask, extent: extent, width: width, height: height)
        let exclusionPixels = exclusion.map { raster($0, extent: extent, width: width, height: height) }

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

        // Positives must sit as deep inside the subject as the shape allows. A subject is a
        // solid body with thin structures hanging off it, and a small neighbourhood test
        // accepts those: scanning row-major then lands every positive in the hair mass at
        // the top of the person, and hair positives make SAM return an edge-ish region that
        // drops the face — measured at 47% of one subject's interior lost. Widest depth
        // that still yields samples wins, so thin subjects degrade instead of failing.
        let shortSide = Double(min(box.width, box.height))
        let probeStep = max(1, Int(shortSide) / 24)
        var core: [Int] = []
        for depthFraction in [0.30, 0.22, 0.16, 0.11, 0.07, 0.04, 0.02] {
            let radius = max(2, Int(depthFraction * shortSide))
            var atDepth: [Int] = []
            var y = minY
            while y <= maxY {
                var x = minX
                while x <= maxX {
                    if isDeepInterior(
                        x: x,
                        y: y,
                        width: width,
                        height: height,
                        pixels: pixels,
                        threshold: onThreshold,
                        radius: radius
                    ) {
                        atDepth.append(y * width + x)
                    }
                    x += probeStep
                }
                y += probeStep
            }
            if atDepth.isEmpty { continue }
            // Keep the deepest samples found so far, and stop as soon as a depth offers
            // enough of them to spread across the subject.
            if core.isEmpty { core = atDepth }
            if atDepth.count >= positiveCount {
                core = atDepth
                break
            }
        }

        var interior: [CGPoint] = []
        interior.reserveCapacity(positiveCount)
        // Even stride across the core spreads the points without chasing extremities, which
        // is what a farthest-first spread would do.
        let coreStep = max(1, core.count / positiveCount)
        var coreIndex = 0
        while coreIndex < core.count && interior.count < positiveCount {
            let idx = core[coreIndex]
            interior.append(
                CGPoint(
                    x: extent.minX + CGFloat(idx % width) + 0.5,
                    y: extent.minY + CGFloat(idx / width) + 0.5
                )
            )
            coreIndex += coreStep
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

        // Split the budget explicitly. Neighbouring people and occluders inside the box are
        // different jobs, and letting the first tier take what it likes starves the second:
        // one shared pool left a plant in front of a group with no negative on it at all.
        let neighbourBudget = min(2, negativeCount / 3)
        let occluderBudget = max(2, negativeCount / 2)

        // Neighbouring people first: these are the negatives that keep per-instance
        // prompts from collapsing back into one group blob where boxes overlap.
        if let exclusionPixels {
            // Contested pixels inside the box matter most, then the ring around it, then
            // anywhere — a far-off neighbour still deserves one "not this person" point.
            let margin = max(pad, Int(shortSide * 0.15))
            let searchStep = max(1, Int(shortSide / 20))
            var insideBox: [CGPoint] = []
            var nearBox: [CGPoint] = []
            var elsewhere: [CGPoint] = []
            var ny = 0
            while ny < height {
                var nx = 0
                while nx < width {
                    let idx = ny * width + nx
                    if exclusionPixels[idx] >= onThreshold, pixels[idx] <= offThreshold {
                        let point = CGPoint(x: CGFloat(nx), y: CGFloat(ny))
                        if nx >= minX, nx <= maxX, ny >= minY, ny <= maxY {
                            insideBox.append(point)
                        } else if nx >= minX - margin, nx <= maxX + margin,
                                  ny >= minY - margin, ny <= maxY + margin {
                            nearBox.append(point)
                        } else {
                            elsewhere.append(point)
                        }
                    }
                    nx += searchStep
                }
                ny += searchStep
            }
            for point in farthestFirst(insideBox + nearBox + elsewhere, limit: neighbourBudget) {
                negatives.append(
                    CGPoint(x: extent.minX + point.x + 0.5, y: extent.minY + point.y + 0.5)
                )
            }
        }

        // Occluders inside the box (a plant in front of a group) get no evidence from
        // outside-box negatives, and the box prompt actively encourages SAM to fill them.
        // Sample background from *within* the box, keeping clear of the subject boundary so
        // a rough mask that undershoots (missed hair) cannot veto real subject pixels.
        // Scale the search to the subject, not the frame: an image-scaled clear radius (71px
        // on a 4288px photo) can only be satisfied by wide-open background, so an occluder
        // *surrounded* by the subject — a leaf across someone's chest — never gets a
        // negative and SAM keeps it. Measured: 40% of the selection was plant.
        let clearRadius = max(2, Int(shortSide * 0.03))
        let gridStep = max(1, Int(shortSide / 20))
        var insideCandidates: [CGPoint] = []
        var y = minY
        while y <= maxY {
            var x = minX
            while x <= maxX {
                if isClearOfMask(
                    x: x,
                    y: y,
                    width: width,
                    height: height,
                    pixels: pixels,
                    threshold: offThreshold,
                    radius: clearRadius
                ) {
                    insideCandidates.append(CGPoint(x: CGFloat(x), y: CGFloat(y)))
                }
                x += gridStep
            }
            y += gridStep
        }
        for point in farthestFirst(insideCandidates, limit: occluderBudget) {
            negatives.append(
                CGPoint(x: extent.minX + point.x + 0.5, y: extent.minY + point.y + 0.5)
            )
        }

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

    private static func raster(
        _ mask: SelectionMask,
        extent: CGRect,
        width: Int,
        height: Int
    ) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height)
        Self.ciContext.render(
            mask.ciImageMatching(extent: extent),
            toBitmap: &pixels,
            rowBytes: width,
            bounds: CGRect(x: extent.minX, y: extent.minY, width: CGFloat(width), height: CGFloat(height)),
            format: .L8,
            colorSpace: CGColorSpaceCreateDeviceGray()
        )
        return pixels
    }

    /// True when the whole neighbourhood is off-mask — a safe place for a negative point.
    private static func isClearOfMask(
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
                if nx < 0 || ny < 0 || nx >= width || ny >= height { continue }
                if pixels[ny * width + nx] > threshold { return false }
            }
        }
        return true
    }

    /// Greedy spread so negatives cover distinct occluders instead of clustering.
    private static func farthestFirst(_ points: [CGPoint], limit: Int) -> [CGPoint] {
        guard limit > 0, !points.isEmpty else { return [] }
        var remaining = points
        var chosen: [CGPoint] = [remaining.removeFirst()]
        while chosen.count < limit, !remaining.isEmpty {
            var bestIndex = 0
            var bestDistance = -1.0
            for (index, candidate) in remaining.enumerated() {
                var nearest = Double.greatestFiniteMagnitude
                for picked in chosen {
                    let dx = Double(candidate.x - picked.x)
                    let dy = Double(candidate.y - picked.y)
                    nearest = min(nearest, dx * dx + dy * dy)
                }
                if nearest > bestDistance {
                    bestDistance = nearest
                    bestIndex = index
                }
            }
            chosen.append(remaining.remove(at: bestIndex))
        }
        return chosen
    }

    /// True when the mask still covers the point at `radius` in every direction — the point
    /// is `radius` deep inside the subject rather than in a strand, a hand, or an edge ramp.
    /// Samples two rings instead of the full disc, which is 24 reads instead of `radius²`.
    private static func isDeepInterior(
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        pixels: [UInt8],
        threshold: UInt8,
        radius: Int
    ) -> Bool {
        let directions = 16
        for scale in [1.0, 0.5] {
            let r = Double(radius) * scale
            for step in 0..<directions {
                let angle = 2 * Double.pi * Double(step) / Double(directions)
                let nx = x + Int((cos(angle) * r).rounded())
                let ny = y + Int((sin(angle) * r).rounded())
                if nx < 0 || ny < 0 || nx >= width || ny >= height { return false }
                if pixels[ny * width + nx] < threshold { return false }
            }
        }
        return true
    }
}
