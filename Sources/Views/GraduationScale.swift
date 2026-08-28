import SwiftUI

/// Measuring-jug graduations down the inside of the carafe's right wall.
///
/// Because Carafe drains, a tick labelled "1,000" marks the level at which
/// 1,000 ml are still *left to drink* — the labels read directly as the remaining
/// amount, which is what the app is for.
///
/// Ticks follow `CarafeShape.unitRightEdge(atUnitY:)` so they hug the wall as it
/// flares through the shoulder rather than sitting on one straight line.
struct GraduationScale: View {
    let goalMillilitres: Double
    let unitSystem: UnitSystem

    /// Gap between the tick and the silhouette, in points.
    private let wallInset: CGFloat = 5
    private let minorTickLength: CGFloat = 5
    private let majorTickLength: CGFloat = 10
    private let labelGap: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let box = CarafeShape.fittedBox(in: CGRect(origin: .zero, size: proxy.size))
            let marks = marks()

            ZStack(alignment: .topLeading) {
                Path { path in
                    for mark in marks {
                        let y = CarafeShape.waterLevelY(for: mark.fraction, in: box)
                        let edge = box.minX + CarafeShape.unitRightEdge(atUnitY: unitY(mark.fraction)) * box.width
                        let outer = edge - wallInset
                        let length = mark.isLabelled ? majorTickLength : minorTickLength
                        path.move(to: CGPoint(x: outer - length, y: y))
                        path.addLine(to: CGPoint(x: outer, y: y))
                    }
                }
                .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1, lineCap: .round))

                ForEach(marks.filter { $0.isLabelled && labelFits($0, in: box) }) { mark in
                    let y = CarafeShape.waterLevelY(for: mark.fraction, in: box)
                    let edge = box.minX + CarafeShape.unitRightEdge(atUnitY: unitY(mark.fraction)) * box.width
                    let text = unitSystem.graduationLabel(forMillilitres: mark.millilitres)
                    let slot: CGFloat = 60

                    Text(text)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .fixedSize()
                        .frame(width: slot, alignment: .trailing)
                        .position(
                            x: edge - wallInset - majorTickLength - labelGap - slot / 2,
                            y: y
                        )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Marks

    private struct Mark: Identifiable {
        let millilitres: Double
        let fraction: Double
        let isLabelled: Bool
        var id: Double { millilitres }
    }

    /// Tick positions from one step above empty up to the goal.
    ///
    /// Capped so an unusually large goal paired with a fine step cannot emit
    /// hundreds of unreadable hairlines.
    private func marks() -> [Mark] {
        guard goalMillilitres > 0 else { return [] }

        let tickStep = unitSystem.tickStepMillilitres
        let labelStep = unitSystem.labelStepMillilitres
        guard tickStep > 0 else { return [] }

        let maximumTicks = 24
        let count = min(Int((goalMillilitres / tickStep).rounded(.down)), maximumTicks)
        guard count > 0 else { return [] }

        return (1...count).map { step in
            let millilitres = Double(step) * tickStep
            // Floating-point steps (fl oz) never land exactly on a multiple, so
            // compare the remainder against a tolerance rather than to zero.
            let remainder = millilitres.truncatingRemainder(dividingBy: labelStep)
            let isLabelled = min(remainder, labelStep - remainder) < tickStep * 0.01
            return Mark(
                millilitres: millilitres,
                fraction: millilitres / goalMillilitres,
                isLabelled: isLabelled
            )
        }
    }

    /// Whether a label has room between the tick and the opposite wall.
    ///
    /// The carafe narrows toward the neck, so the highest marks can sit where a
    /// four-digit label would punch straight through the left edge. Those keep
    /// their tick and lose the label rather than rendering something broken.
    private func labelFits(_ mark: Mark, in box: CGRect) -> Bool {
        let edgeUnit = CarafeShape.unitRightEdge(atUnitY: unitY(mark.fraction))
        let rightEdge = box.minX + edgeUnit * box.width
        let leftEdge = box.minX + (1 - edgeUnit) * box.width

        let labelRight = rightEdge - wallInset - majorTickLength - labelGap
        let text = unitSystem.graduationLabel(forMillilitres: mark.millilitres)
        // 9pt rounded digits run a little over half their point size in width.
        let estimatedWidth = CGFloat(text.count) * 5.4 + 2

        return labelRight - estimatedWidth >= leftEdge + wallInset
    }

    /// The unit-square Y a fill fraction maps to, matching `CarafeShape.waterLevelY`.
    private func unitY(_ fraction: Double) -> CGFloat {
        let clamped = min(1, max(0, fraction))
        return CarafeShape.waterBottomY - (CarafeShape.waterBottomY - CarafeShape.waterTopY) * clamped
    }
}

#Preview("Graduations") {
    ZStack {
        CarafeShape().strokeBorder(.primary.opacity(0.55), lineWidth: 2)
        GraduationScale(goalMillilitres: 2000, unitSystem: .metric)
    }
    .frame(width: 180, height: 250)
    .padding(40)
}
