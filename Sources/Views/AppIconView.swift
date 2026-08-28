import SwiftUI

/// The app icon artwork, drawn from the same `CarafeShape` as everything else.
///
/// Rendering the icon from the shape rather than hand-drawing a PNG means the
/// icon can never drift away from the menu bar glyph or the gauge. The asset
/// catalog PNGs are generated from this view — see `IconGeneratorTests`.
///
/// Everything scales off `size` so the artwork is resolution-independent: the
/// same view produces a legible 16pt icon and a crisp 1024pt one.
struct AppIconView: View {
    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                background(size: size)
                carafe(size: size)
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// The rounded-square plate macOS icons sit on.
    ///
    /// `cornerRadius / size = 0.2237` matches Apple's icon grid, and `.continuous`
    /// gives the squircle curvature rather than a plain circular arc.
    private func background(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.42, green: 0.76, blue: 0.97),
                        Color(red: 0.13, green: 0.42, blue: 0.80),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // A soft highlight across the top stops the plate looking flat.
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.28), location: 0),
                                .init(color: .clear, location: 0.45),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: size, height: size)
    }

    private func carafe(size: CGFloat) -> some View {
        // Occupies ~62% of the plate height, which keeps it inside the optical
        // margin Apple's grid expects.
        let height = size * 0.62
        let width = height * CarafeShape.aspectRatio
        let stroke = size * 0.035

        return ZStack {
            // Water sitting at roughly two thirds — a carafe in use, not an empty one.
            WaterSurface(levelFraction: 0.66, phase: 0.7, amplitude: size * 0.012)
                .fill(.white.opacity(0.92))
                .clipShape(CarafeShape().inset(by: stroke / 2))

            CarafeShape()
                .strokeBorder(.white, lineWidth: stroke)
        }
        .frame(width: width, height: height)
    }
}

#Preview("App icon") {
    VStack(spacing: 20) {
        AppIconView().frame(width: 256, height: 256)

        HStack(alignment: .bottom, spacing: 16) {
            ForEach([16.0, 32.0, 64.0, 128.0], id: \.self) { size in
                AppIconView().frame(width: size, height: size)
            }
        }
    }
    .padding(40)
}
