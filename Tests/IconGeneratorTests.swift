import SwiftUI
import XCTest

@testable import Carafe

/// Generates the app icon PNGs from `AppIconView`.
///
/// Not a test of behaviour — a build step wearing a test's clothes, because
/// `ImageRenderer` needs a host app process to run in. Regenerate with:
///
/// ```
/// ./Scripts/generate-icon.sh
/// ```
///
/// Without `CARAFE_ICON_DIR` set it renders to a temporary directory and merely
/// asserts that every required size produces a valid image, so CI still catches
/// artwork that fails to render.
@MainActor
final class IconGeneratorTests: XCTestCase {
    /// Point size and scale for each entry in `AppIcon.appiconset/Contents.json`.
    private static let variants: [(points: Int, scale: Int)] = [
        (16, 1), (16, 2),
        (32, 1), (32, 2),
        (128, 1), (128, 2),
        (256, 1), (256, 2),
        (512, 1), (512, 2),
    ]

    func testGenerateAppIconSet() throws {
        let directory: URL
        let isGenerating: Bool
        if let custom = ProcessInfo.processInfo.environment["CARAFE_ICON_DIR"] {
            directory = URL(fileURLWithPath: custom, isDirectory: true)
            isGenerating = true
        } else {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("carafe-icon-\(UUID().uuidString)", isDirectory: true)
            isGenerating = false
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { if !isGenerating { try? FileManager.default.removeItem(at: directory) } }

        for variant in Self.variants {
            let points = CGFloat(variant.points)
            let renderer = ImageRenderer(
                content: AppIconView().frame(width: points, height: points)
            )
            renderer.scale = CGFloat(variant.scale)
            // The rounded plate must keep its transparent corners.
            renderer.isOpaque = false

            let name = variant.scale == 1
                ? "icon_\(variant.points)x\(variant.points).png"
                : "icon_\(variant.points)x\(variant.points)@2x.png"

            let image = try XCTUnwrap(renderer.cgImage, "no image for \(name)")
            let expected = variant.points * variant.scale
            XCTAssertEqual(image.width, expected, "\(name) has the wrong pixel width")
            XCTAssertEqual(image.height, expected, "\(name) has the wrong pixel height")

            let data = try XCTUnwrap(
                NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
                "could not encode \(name)"
            )
            try data.write(to: directory.appendingPathComponent(name))
        }
    }
}
