import AppKit
import SwiftUI

/// Renders `CarafeShape` into a template `NSImage` for the menu bar.
///
/// Going through `ImageRenderer` rather than handing SwiftUI the shape directly
/// buys two things that matter in the menu bar:
///
/// - **Template rendering.** `isTemplate = true` lets AppKit derive the light and
///   dark appearances, the "menu bar is selected" inversion, and the reduced
///   contrast when the app is inactive. Reimplementing that in SwiftUI is
///   guesswork that goes subtly wrong.
/// - **Crisp hairlines.** Rasterising once at a known scale with a stroke width
///   chosen for that size avoids the blurry half-pixel edges you get when a 1pt
///   stroke is scaled into an arbitrary label frame.
///
/// The image is cached because SwiftUI re-evaluates the label on every state
/// change, and re-rasterising a vector on each pass would be wasteful.
@MainActor
enum MenuBarIcon {
    /// Drawn height in points. The system menu bar is 22pt tall; 17 leaves the
    /// standard optical margin above and below.
    static let height: CGFloat = 17

    private static var cache: [CacheKey: NSImage] = [:]

    private struct CacheKey: Hashable {
        let height: CGFloat
        let scale: CGFloat
        let attention: Bool
    }

    /// The menu bar icon at the default size.
    ///
    /// - Parameter attention: draws a filled badge beside the carafe. Used by the
    ///   in-app reminder fallback, when system notifications are unavailable — it
    ///   is the only signal the app has that needs no entitlement.
    static func standard(attention: Bool = false) -> NSImage {
        image(height: height, attention: attention)
    }

    static func image(height: CGFloat, attention: Bool = false, scale: CGFloat? = nil) -> NSImage {
        let renderScale = scale ?? NSScreen.main?.backingScaleFactor ?? 2
        let key = CacheKey(height: height, scale: renderScale, attention: attention)
        if let cached = cache[key] { return cached }

        let carafeWidth = (height * CarafeShape.aspectRatio).rounded()
        let badgeDiameter = (height * 0.30).rounded()
        let badgeGap: CGFloat = 1
        let width = attention ? carafeWidth + badgeGap + badgeDiameter : carafeWidth

        // Heavier relative stroke at small sizes, or the outline disappears once
        // AppKit tints it down for an inactive menu bar.
        let lineWidth: CGFloat = height <= 20 ? 1.3 : 1.6

        let content = HStack(alignment: .top, spacing: badgeGap) {
            CarafeShape()
                .strokeBorder(Color.black, lineWidth: lineWidth)
                .frame(width: carafeWidth, height: height)

            if attention {
                Circle()
                    .fill(Color.black)
                    .frame(width: badgeDiameter, height: badgeDiameter)
                    .padding(.top, height * 0.12)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)

        let renderer = ImageRenderer(content: content)
        renderer.scale = renderScale
        renderer.isOpaque = false

        let size = NSSize(width: width, height: height)
        let image: NSImage
        if let cgImage = renderer.cgImage {
            image = NSImage(cgImage: cgImage, size: size)
        } else {
            // Should not happen, but an empty image beats a crash in a menu bar app.
            image = NSImage(size: size)
        }
        // The alpha channel defines the glyph; AppKit supplies the colour.
        image.isTemplate = true

        cache[key] = image
        return image
    }
}
