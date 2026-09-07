import AppKit
import CoreImage
import Foundation
@testable import LaughPlayer

/// Comparable, provider-agnostic scores for selection mattes (W3-08e).
/// Metrics are external (coverage / boundary softness / timing) — not CoreML internals.
struct SelectionFixtureScore: Equatable, Sendable {
    let fixture: String
    let providerID: String
    let ok: Bool
    /// Fraction of pixels above threshold (0…1).
    let coverage: Double
    /// Softness of the uncertain boundary band (0…1). Higher = softer fringe.
    let boundarySoftness: Double
    let elapsedMs: Double
    let errorDescription: String?
}

struct SelectionMeasurementSummary: Equatable, Sendable {
    let providerID: String
    let scores: [SelectionFixtureScore]

    var personScores: [SelectionFixtureScore] {
        scores.filter { SelectionMeasurementHarness.personFixtures.contains($0.fixture) }
    }

    var negativeScores: [SelectionFixtureScore] {
        scores.filter { SelectionMeasurementHarness.negativeFixtures.contains($0.fixture) }
    }

    /// Mean coverage on successful person fixtures (0 if none).
    var meanPersonCoverage: Double {
        let ok = personScores.filter(\.ok)
        guard !ok.isEmpty else { return 0 }
        return ok.map(\.coverage).reduce(0, +) / Double(ok.count)
    }

    var meanPersonMs: Double {
        let ok = personScores.filter(\.ok)
        guard !ok.isEmpty else { return 0 }
        return ok.map(\.elapsedMs).reduce(0, +) / Double(ok.count)
    }

    var meanBoundarySoftness: Double {
        let ok = personScores.filter(\.ok)
        guard !ok.isEmpty else { return 0 }
        return ok.map(\.boundarySoftness).reduce(0, +) / Double(ok.count)
    }

    /// Negatives that incorrectly produced a non-empty matte.
    var negativeFalsePositives: Int {
        negativeScores.filter { $0.ok && $0.coverage > 0.02 }.count
    }
}

/// Fixture eval harness so MobileSAM → EfficientSAM3/SAM2 swaps stay comparable.
enum SelectionMeasurementHarness {
    static let logPrefix = "[SEL-MEASURE]"

    static let personFixtures: [String] = [
        "person-portrait-studio.jpg",
        "person-portrait-2k.jpg",
        "person-fullbody-street.jpg"
    ]

    static let negativeFixtures: [String] = [
        "negative-blank.jpg",
        "negative-gradient.jpg",
        "synthetic-silhouette.jpg"
    ]

    static var allFixtures: [String] { personFixtures + negativeFixtures }

    static var fixturesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Selection", isDirectory: true)
    }

    static func loadCIImage(named name: String, from directory: URL = fixturesDirectory) throws -> CIImage {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SelectionError.invalidImage
        }
        guard let ns = NSImage(contentsOf: url),
              let tiff = ns.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage
        else {
            throw SelectionError.invalidImage
        }
        return CIImage(cgImage: cg)
    }

    /// Score one fixture. Person fixtures use class/center prompt; negatives expect empty/miss.
    static func score(
        fixture: String,
        image: CIImage,
        provider: SelectionProvider,
        quality: SelectionQuality = .accurate,
        expectPerson: Bool
    ) async -> SelectionFixtureScore {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let mask: SelectionMask
            if expectPerson {
                mask = try await selectPersonLike(provider: provider, image: image, quality: quality)
            } else {
                do {
                    mask = try await selectPersonLike(provider: provider, image: image, quality: quality)
                } catch let error as SelectionError {
                    switch error {
                    case .emptyResult, .pointMiss, .unsupportedClass:
                        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
                        return SelectionFixtureScore(
                            fixture: fixture,
                            providerID: provider.providerID,
                            ok: true,
                            coverage: 0,
                            boundarySoftness: 0,
                            elapsedMs: ms,
                            errorDescription: nil
                        )
                    default:
                        throw error
                    }
                }
            }
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let coverage = matteCoverage(mask)
            let softness = boundarySoftness(mask)
            let ok: Bool
            if expectPerson {
                ok = coverage > 0.02
            } else {
                ok = coverage <= 0.02
            }
            return SelectionFixtureScore(
                fixture: fixture,
                providerID: provider.providerID,
                ok: ok,
                coverage: coverage,
                boundarySoftness: softness,
                elapsedMs: ms,
                errorDescription: ok ? nil : (expectPerson ? "lowCoverage" : "falsePositive")
            )
        } catch {
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            if !expectPerson {
                return SelectionFixtureScore(
                    fixture: fixture,
                    providerID: provider.providerID,
                    ok: true,
                    coverage: 0,
                    boundarySoftness: 0,
                    elapsedMs: ms,
                    errorDescription: nil
                )
            }
            return SelectionFixtureScore(
                fixture: fixture,
                providerID: provider.providerID,
                ok: false,
                coverage: 0,
                boundarySoftness: 0,
                elapsedMs: ms,
                errorDescription: String(describing: error)
            )
        }
    }

    static func runSuite(
        provider: SelectionProvider,
        quality: SelectionQuality = .accurate,
        fixturesDirectory: URL = fixturesDirectory
    ) async -> SelectionMeasurementSummary {
        var scores: [SelectionFixtureScore] = []
        for name in personFixtures {
            do {
                let image = try loadCIImage(named: name, from: fixturesDirectory)
                scores.append(
                    await score(
                        fixture: name,
                        image: image,
                        provider: provider,
                        quality: quality,
                        expectPerson: true
                    )
                )
            } catch {
                scores.append(
                    SelectionFixtureScore(
                        fixture: name,
                        providerID: provider.providerID,
                        ok: false,
                        coverage: 0,
                        boundarySoftness: 0,
                        elapsedMs: 0,
                        errorDescription: "loadFailed"
                    )
                )
            }
        }
        for name in negativeFixtures {
            do {
                let image = try loadCIImage(named: name, from: fixturesDirectory)
                scores.append(
                    await score(
                        fixture: name,
                        image: image,
                        provider: provider,
                        quality: quality,
                        expectPerson: false
                    )
                )
            } catch {
                scores.append(
                    SelectionFixtureScore(
                        fixture: name,
                        providerID: provider.providerID,
                        ok: false,
                        coverage: 0,
                        boundarySoftness: 0,
                        elapsedMs: 0,
                        errorDescription: "loadFailed"
                    )
                )
            }
        }
        return SelectionMeasurementSummary(providerID: provider.providerID, scores: scores)
    }

    static func logSummary(_ summary: SelectionMeasurementSummary) {
        print("\(logPrefix) provider=\(summary.providerID)")
        for row in summary.scores {
            let err = row.errorDescription.map { " err=\($0)" } ?? ""
            print(
                String(
                    format: "%@ fixture=%@ ok=%@ cov=%.4f soft=%.4f ms=%.1f%@",
                    logPrefix,
                    row.fixture,
                    row.ok ? "true" : "false",
                    row.coverage,
                    row.boundarySoftness,
                    row.elapsedMs,
                    err
                )
            )
        }
        print(
            String(
                format: "%@ summary personCov=%.4f personMs=%.1f soft=%.4f negFP=%d",
                logPrefix,
                summary.meanPersonCoverage,
                summary.meanPersonMs,
                summary.meanBoundarySoftness,
                summary.negativeFalsePositives
            )
        )
    }

    // MARK: - Prompt routing (class-blind prefer prompt; Vision uses class)

    private static func selectPersonLike(
        provider: SelectionProvider,
        image: CIImage,
        quality: SelectionQuality
    ) async throws -> SelectionMask {
        if provider.providerID == VisionPersonSelectionProvider.id {
            return try await provider.selectClass(in: image, class: .person, quality: quality)
        }
        let center = CGPoint(x: image.extent.midX, y: image.extent.midY)
        return try await provider.select(in: image, prompt: .point(center), quality: quality)
    }

    // MARK: - Accuracy against ground truth

    /// Precision scores for a matte (or a rendered ants path) against a known silhouette.
    struct AccuracyScore: Equatable, Sendable {
        let iou: Double
        /// Mean signed boundary offset in pixels. Positive = prediction sits *outside* truth,
        /// which is what a matte thresholded below half-coverage looks like.
        let boundaryOffsetPx: Double
    }

    static func accuracy(prediction: [UInt8], truth: [UInt8], width: Int, height: Int) -> AccuracyScore {
        precondition(prediction.count == width * height && truth.count == width * height)
        var intersection = 0
        var union = 0
        var predictedArea = 0
        var truthArea = 0
        for i in 0..<(width * height) {
            let p = prediction[i] > 127
            let t = truth[i] > 127
            if p { predictedArea += 1 }
            if t { truthArea += 1 }
            if p && t { intersection += 1 }
            if p || t { union += 1 }
        }
        let iou = union > 0 ? Double(intersection) / Double(union) : 0

        // Area difference spread over the truth perimeter approximates a mean edge shift.
        var perimeter = 0
        for y in 0..<height {
            for x in 0..<width where truth[y * width + x] > 127 {
                let leftOff = x == 0 || truth[y * width + x - 1] <= 127
                let rightOff = x == width - 1 || truth[y * width + x + 1] <= 127
                let downOff = y == 0 || truth[(y - 1) * width + x] <= 127
                let upOff = y == height - 1 || truth[(y + 1) * width + x] <= 127
                if leftOff || rightOff || downOff || upOff { perimeter += 1 }
            }
        }
        let offset = perimeter > 0 ? Double(predictedArea - truthArea) / Double(perimeter) : 0
        return AccuracyScore(iou: iou, boundaryOffsetPx: offset)
    }

    /// Rasterises a matte to a binary L8 buffer at `extent` resolution.
    static func binaryRaster(_ matte: CIImage, extent: CGRect, context: CIContext) -> [UInt8] {
        let width = max(1, Int(extent.width.rounded()))
        let height = max(1, Int(extent.height.rounded()))
        var buf = [UInt8](repeating: 0, count: width * height)
        context.render(
            matte,
            toBitmap: &buf,
            rowBytes: width,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .L8,
            colorSpace: CGColorSpaceCreateDeviceGray()
        )
        return buf
    }

    /// Rasterises a filled CGPath to a binary L8 buffer (bottom-left origin, like CIImage).
    static func binaryRaster(path: CGPath, width: Int, height: Int) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: width * height)
        guard let ctx = CGContext(
            data: &buf,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return buf }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.addPath(path)
        ctx.fillPath(using: .evenOdd)
        return buf
    }

    // MARK: - Metrics

    static func matteCoverage(_ mask: SelectionMask, threshold: UInt8 = 32) -> Double {
        let extent = mask.extent.integral
        let width = max(1, Int(extent.width.rounded()))
        let height = max(1, Int(extent.height.rounded()))
        var buf = [UInt8](repeating: 0, count: width * height)
        let ctx = CIContext(options: [.cacheIntermediates: false])
        ctx.render(
            mask.ciImageMatching(extent: extent),
            toBitmap: &buf,
            rowBytes: width,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            format: .L8,
            colorSpace: CGColorSpaceCreateDeviceGray()
        )
        var on = 0
        for value in buf where value > threshold { on += 1 }
        return Double(on) / Double(width * height)
    }

    /// Mean photo gradient magnitude along the matte boundary (0…1).
    ///
    /// No ground truth needed: a boundary that sits on real image structure scores high,
    /// while one floating through flat colour (the fuzzy-upsample failure mode) scores low.
    static func edgeAgreement(mask: SelectionMask, photo: CIImage) -> Double {
        let extent = mask.extent.integral
        let width = max(1, Int(extent.width.rounded()))
        let height = max(1, Int(extent.height.rounded()))
        let context = CIContext(options: [.cacheIntermediates: false])
        let matte = mask.ciImageMatching(extent: extent)

        let radius: Float = 2
        let clamped = matte.clampedToExtent()
        let band = clamped
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
            .applyingFilter("CIDifferenceBlendMode", parameters: [
                kCIInputBackgroundImageKey: clamped
                    .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: radius])
            ])
            .cropped(to: extent)
        let edges = photo
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1.0])
            .cropped(to: extent)

        let bandBuf = binaryRaster(band, extent: extent, context: context)
        let edgeBuf = binaryRaster(edges, extent: extent, context: context)
        var sum = 0.0
        var count = 0
        for i in 0..<(width * height) where bandBuf[i] > 16 {
            sum += Double(edgeBuf[i]) / 255.0
            count += 1
        }
        return count > 0 ? sum / Double(count) : 0
    }

    /// Mean normalized alpha in the dilate−erode band (soft edges → mid values).
    static func boundarySoftness(_ mask: SelectionMask) -> Double {
        let extent = mask.extent.integral
        let matte = mask.ciImageMatching(extent: extent)
        let radius: Float = 2
        let clamped = matte.clampedToExtent()
        let dilated = clamped
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
        let eroded = clamped
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
        guard let band = CIFilter(name: "CIDifferenceBlendMode", parameters: [
            kCIInputImageKey: dilated,
            kCIInputBackgroundImageKey: eroded
        ])?.outputImage?.cropped(to: extent) else {
            return 0
        }
        guard let gated = CIFilter(name: "CIMultiplyCompositing", parameters: [
            kCIInputImageKey: matte,
            kCIInputBackgroundImageKey: band
        ])?.outputImage?.cropped(to: extent) else {
            return 0
        }

        let width = max(1, Int(extent.width.rounded()))
        let height = max(1, Int(extent.height.rounded()))
        var matteBuf = [UInt8](repeating: 0, count: width * height)
        var bandBuf = [UInt8](repeating: 0, count: width * height)
        let ctx = CIContext(options: [.cacheIntermediates: false])
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        ctx.render(
            gated,
            toBitmap: &matteBuf,
            rowBytes: width,
            bounds: bounds,
            format: .L8,
            colorSpace: CGColorSpaceCreateDeviceGray()
        )
        ctx.render(
            band,
            toBitmap: &bandBuf,
            rowBytes: width,
            bounds: bounds,
            format: .L8,
            colorSpace: CGColorSpaceCreateDeviceGray()
        )
        var sum = 0.0
        var count = 0
        let pixelCount = width * height
        for i in 0..<pixelCount where bandBuf[i] > 16 {
            let v = Double(matteBuf[i])
            let soft = 1.0 - abs(v - 128.0) / 128.0
            sum += soft
            count += 1
        }
        guard count > 0 else { return 0 }
        return sum / Double(count)
    }
}
