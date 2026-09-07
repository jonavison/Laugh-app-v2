import XCTest
import CoreImage
@testable import LaughPlayer

/// Pins the prompt coordinate convention.
///
/// SamKit reads prompt points and boxes with a **top-left** origin, while Core Image uses
/// bottom-left. `SelectionPromptBuilder` reads a rendered raster by row index, which is also
/// top-down, so its output already matches SamKit — the two conventions line up only because
/// both are top-down. "Correcting" either one in isolation silently flips every prompt, and a
/// flip is invisible on a centred subject, so these tests use an off-centre subject.
final class SelectionCoordinateConventionTests: XCTestCase {
    private let side: CGFloat = 384

    /// Two flat squares: one high in CI space, one low. Any flip swaps which is selected.
    private func twoSquarePhoto() -> (photo: CIImage, extent: CGRect, high: CGRect, low: CGRect) {
        let extent = CGRect(x: 0, y: 0, width: side, height: side)
        let high = CGRect(x: 120, y: 250, width: 140, height: 100)
        let low = CGRect(x: 120, y: 30, width: 140, height: 100)
        let background = CIImage(color: CIColor(red: 0.45, green: 0.45, blue: 0.47)).cropped(to: extent)
        let highFill = CIImage(color: CIColor(red: 0.85, green: 0.15, blue: 0.1)).cropped(to: high)
        let lowFill = CIImage(color: CIColor(red: 0.1, green: 0.2, blue: 0.85)).cropped(to: low)
        let photo = lowFill.composited(over: highFill.composited(over: background)).cropped(to: extent)
        return (photo, extent, high, low)
    }

    /// CI rect → top-left-origin rect.
    private func flipped(_ rect: CGRect, in extent: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: extent.height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Mean matte coverage inside a CI rect — measured in CI space, so no raster row-order
    /// assumption can contaminate the answer.
    private func meanCoverage(_ matte: CIImage, in rect: CGRect, context: CIContext) -> Double {
        let average = matte.applyingFilter("CIAreaAverage", parameters: [
            kCIInputExtentKey: CIVector(cgRect: rect)
        ])
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            average,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return Double(pixel[0]) / 255.0
    }

    func testSamPromptPointsUseTopLeftOrigin() async throws {
        let store = SelectionModelStore()
        guard store.isReady(SelectionModelArtifact.mobileSAM) else {
            throw XCTSkip("MobileSAM not cached")
        }
        let (photo, extent, high, low) = twoSquarePhoto()
        let context = CIContext(options: [.cacheIntermediates: false])
        let provider = MobileSAMSelectionProvider(store: store, applyPolish: false)

        // Point at the high square expressed top-left, which is what SamKit expects.
        let topLeftHigh = flipped(high, in: extent)
        let mask = try await provider.select(
            in: photo,
            prompt: .point(CGPoint(x: topLeftHigh.midX, y: topLeftHigh.midY)),
            quality: .accurate
        )
        let matte = mask.ciImageMatching(extent: extent)
        let onHigh = meanCoverage(matte, in: high, context: context)
        let onLow = meanCoverage(matte, in: low, context: context)
        print("[COORD] topLeftPrompt highCoverage=\(onHigh) lowCoverage=\(onLow)")

        XCTAssertGreaterThan(onHigh, 0.7, "top-left prompt should select the square it names")
        XCTAssertLessThan(onLow, 0.3, "selecting the other square means the convention flipped")
    }

    func testPromptBuilderEmitsTopLeftCoordinates() throws {
        let (_, extent, high, low) = twoSquarePhoto()
        let context = CIContext(options: [.cacheIntermediates: false])
        let roughCI = CIImage(color: .white).cropped(to: high)
            .composited(over: CIImage(color: .black).cropped(to: extent))
            .cropped(to: extent)
        guard let roughCG = context.createCGImage(roughCI, from: extent) else {
            return XCTFail("rough cg")
        }
        let rough = SelectionMask(
            cgImage: roughCG,
            extent: extent,
            confidence: 1,
            semanticClass: .person,
            source: .pointPrompt
        )
        let prompt = SelectionPromptBuilder.fromRoughMask(rough, imageExtent: extent)
        let expected = flipped(high, in: extent)
        print("[COORD] builder pos=\(prompt.positivePoints) expectedSubject=\(expected)")

        XCTAssertFalse(prompt.positivePoints.isEmpty)
        for point in prompt.positivePoints {
            XCTAssertTrue(
                expected.insetBy(dx: -2, dy: -2).contains(point),
                "positive \(point) is not on the subject in top-left space"
            )
        }
        for point in prompt.negativePoints {
            XCTAssertFalse(expected.contains(point), "negative \(point) landed on the subject")
        }
        let box = try XCTUnwrap(prompt.box)
        XCTAssertTrue(box.insetBy(dx: -12, dy: -12).contains(expected), "box should enclose the subject")
        XCTAssertFalse(box.contains(flipped(low, in: extent)), "box should not span the far square")
    }
}
