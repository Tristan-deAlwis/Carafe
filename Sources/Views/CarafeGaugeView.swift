import SwiftUI

/// The see-through carafe: glass, water, graduations, outline.
///
/// Purely presentational — it takes a fill fraction and a goal, and knows nothing
/// about the store. That keeps it previewable at any level and reusable for the
/// app icon renderer.
///
/// Motion is deliberately restrained. The level animates when it changes, and the
/// surface only ripples while `animateWaves` is true, which the popover sets to
/// false the moment it closes. A menu bar app that is idle should cost nothing.
struct CarafeGaugeView: View {
    /// How full the carafe is, 0 (goal met) to 1 (untouched).
    let fillFraction: Double
    let goalMillilitres: Double
    let unitSystem: UnitSystem

    /// Drives the surface ripple. Set false whenever the view is not visible.
    var animateWaves: Bool = false

    var showGraduations: Bool = true

    private let waveAmplitude: CGFloat = 2.5
    private let waveSpeed: Double = 0.9
    private let outlineWidth: CGFloat = 1.75

    var body: some View {
        ZStack {
            glassBody
            water
            graduations
            outline
        }
        .compositingGroup()
        .accessibilityElement()
        .accessibilityLabel("Carafe")
        .accessibilityValue(
            "\(unitSystem.format(millilitres: fillFraction * goalMillilitres)) remaining today"
        )
    }

    // MARK: - Layers

    /// The barely-there tint that reads as glass, plus a specular highlight down
    /// the left side so the vessel looks curved rather than flat.
    private var glassBody: some View {
        ZStack {
            CarafeShape()
                .fill(Color.primary.opacity(0.045))

            CarafeShape()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .white.opacity(0.22), location: 0.0),
                            .init(color: .white.opacity(0.05), location: 0.28),
                            .init(color: .clear, location: 0.55),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }

    private var water: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !animateWaves)) { timeline in
            let phase = animateWaves
                ? timeline.date.timeIntervalSinceReferenceDate * waveSpeed
                : 0.8  // a still meniscus when at rest

            WaterSurface(
                levelFraction: fillFraction,
                phase: phase,
                amplitude: waveAmplitude
            )
            .fill(waterGradient)
            .clipShape(CarafeShape().inset(by: outlineWidth / 2))
            .animation(.smooth(duration: 0.55), value: fillFraction)
        }
    }

    private var waterGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.38, green: 0.74, blue: 0.95).opacity(0.72),
                Color(red: 0.16, green: 0.47, blue: 0.84).opacity(0.88),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    @ViewBuilder
    private var graduations: some View {
        if showGraduations {
            GraduationScale(goalMillilitres: goalMillilitres, unitSystem: unitSystem)
        }
    }

    private var outline: some View {
        CarafeShape()
            .strokeBorder(Color.primary.opacity(0.55), lineWidth: outlineWidth)
    }
}

// MARK: - Previews

#Preview("Draining through the day") {
    HStack(spacing: 18) {
        ForEach([1.0, 0.75, 0.5, 0.25, 0.0], id: \.self) { level in
            VStack(spacing: 8) {
                CarafeGaugeView(fillFraction: level, goalMillilitres: 2000, unitSystem: .metric)
                    .frame(width: 110, height: 155)
                Text(UnitSystem.metric.format(millilitres: level * 2000))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding(30)
}

#Preview("Fluid ounces") {
    CarafeGaugeView(
        fillFraction: 0.6,
        goalMillilitres: 64 * UnitSystem.millilitresPerUSFluidOunce,
        unitSystem: .us
    )
    .frame(width: 150, height: 210)
    .padding(40)
}
