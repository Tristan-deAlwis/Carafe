import SwiftUI

/// The body of water inside the carafe: everything below a gently curved surface.
///
/// Drawn across the full rect and then clipped to `CarafeShape` by the caller, so
/// the water takes the carafe's edges exactly without this shape needing to know
/// the silhouette. It aligns to the same fitted box `CarafeShape` uses.
///
/// The surface is a shallow sine wave rather than a flat line. At rest it reads as
/// a meniscus; when `phase` is animated it becomes a slow swell. `phase` is only
/// driven while the popover is open — see `CarafeGaugeView`.
struct WaterSurface: Shape {
    /// How full the carafe is, 0 (empty) to 1 (full).
    var levelFraction: Double

    /// Wave phase in radians. Animate for motion; leave fixed for a still meniscus.
    var phase: Double

    /// Wave height in points, peak to centre.
    var amplitude: CGFloat

    /// Number of full sine periods across the carafe's width.
    var waveCount: Double = 1.4

    /// Animating both the level and the phase keeps the surface continuous while
    /// the water drops after a drink.
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(levelFraction, phase) }
        set {
            levelFraction = newValue.first
            phase = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        guard levelFraction > 0, rect.width > 0 else { return Path() }

        let box = CarafeShape.fittedBox(in: rect)
        let levelY = CarafeShape.waterLevelY(for: levelFraction, in: box)

        // Flatten the wave as the carafe approaches full or empty, so the surface
        // never breaks the silhouette's rim or floats above a dry base.
        let edgeProximity = min(levelFraction, 1 - levelFraction) / 0.08
        let effectiveAmplitude = amplitude * min(1, max(0, edgeProximity))

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: levelY))

        if effectiveAmplitude > 0.01 {
            let steps = 48
            for step in 0...steps {
                let t = Double(step) / Double(steps)
                let x = rect.minX + rect.width * t
                let angle = t * waveCount * 2 * .pi + phase
                path.addLine(to: CGPoint(x: x, y: levelY + sin(angle) * effectiveAmplitude))
            }
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: levelY))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Previews

#Preview("Water levels") {
    HStack(spacing: 16) {
        ForEach([1.0, 0.66, 0.33, 0.0], id: \.self) { level in
            ZStack {
                WaterSurface(levelFraction: level, phase: 0.6, amplitude: 3)
                    .fill(.blue.opacity(0.55))
                CarafeShape()
                    .strokeBorder(.primary.opacity(0.55), lineWidth: 2)
            }
            .clipShape(CarafeShape())
            .overlay {
                CarafeShape().strokeBorder(.primary.opacity(0.55), lineWidth: 2)
            }
            .frame(width: 90, height: 130)
        }
    }
    .padding(30)
}
