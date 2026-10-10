import XCTest
@testable import LaughPlayer

/// Renders website before/after stills through the real export pipeline.
/// Opt-in: `LAUGH_MARKETING_RENDER=<dir> ./scripts/test.sh --filter MarketingEditRenderTests`
/// `<dir>/manifest.json`: `[{"name": "lake", "preset": "Fuji", "set": {"exposure": 0.3}}]`.
/// `preset` (optional) seeds the parameters; `set` (optional) overrides individual sliders.
/// Reads `<name>.png`, writes `out/<name>-before.jpg` + `out/<name>-after.jpg`.
final class MarketingEditRenderTests: XCTestCase {
    private struct Entry: Decodable {
        let name: String
        let preset: String?
        let set: [String: Double]?
    }

    func testRenderMarketingStills() throws {
        guard let dirPath = ProcessInfo.processInfo.environment["LAUGH_MARKETING_RENDER"] else {
            throw XCTSkip("Set LAUGH_MARKETING_RENDER to render marketing stills.")
        }
        let dir = URL(fileURLWithPath: dirPath)
        let out = dir.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let entries = try JSONDecoder().decode(
            [Entry].self,
            from: Data(contentsOf: dir.appendingPathComponent("manifest.json"))
        )

        var options = ImageExportOptions.default
        options.quality = 90

        for entry in entries {
            var base = ImageAdjustParameters.identity
            if let presetTitle = entry.preset {
                base = try XCTUnwrap(
                    ImageAdjustPreset.allCases.first { $0.title == presetTitle },
                    "Unknown preset \(presetTitle)"
                ).parameters
            }
            let parameters = try overriding(base, with: entry.set ?? [:])
            let source = dir.appendingPathComponent("\(entry.name).png")
            for (suffix, params) in [("before", ImageAdjustParameters.identity), ("after", parameters)] {
                let image = try XCTUnwrap(
                    ImageExportWriter.renderCGImage(
                        sourceURL: source,
                        parameters: params,
                        quarterTurns: 0,
                        exportOptions: options
                    ),
                    "Render failed for \(entry.name)"
                )
                try ImageExportWriter.write(
                    image,
                    to: out.appendingPathComponent("\(entry.name)-\(suffix).jpg"),
                    options: options
                )
            }
        }
    }

    private func overriding(
        _ base: ImageAdjustParameters,
        with values: [String: Double]
    ) throws -> ImageAdjustParameters {
        var dict = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(base)) as? [String: Any]
        )
        for (key, value) in values {
            XCTAssertNotNil(dict[key], "Unknown parameter \(key)")
            dict[key] = value
        }
        return try JSONDecoder().decode(
            ImageAdjustParameters.self,
            from: JSONSerialization.data(withJSONObject: dict)
        )
    }
}
