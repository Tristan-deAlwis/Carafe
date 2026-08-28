import SwiftUI

/// Corrects the amount drunk on a past day (or today).
///
/// Reached by clicking a bar in the history strip. The carafe still drains, so the
/// gauge reads as "what was left" — but the number being edited is the amount
/// *drunk*, which is what you actually remember and want to correct, so it is
/// labelled explicitly rather than left to inference.
struct DayEditorView: View {
    let date: Date

    @Environment(HydrationStore.self) private var store
    @FocusState private var amountFocused: Bool

    private var day: DayLog {
        store.log(for: date) ?? DayLog(date: date, goalMillilitres: store.goalMillilitres)
    }

    var body: some View {
        VStack(spacing: 12) {
            CarafeGaugeView(
                fillFraction: day.fillFraction,
                goalMillilitres: day.goalMillilitres,
                unitSystem: store.unitSystem
            )
            .frame(width: 96, height: 134)

            amountEditor

            // An empty carafe means the goal was met, which is the good outcome — but
            // "empty" reads as "drank nothing" at a glance, so say which it is.
            HStack(spacing: 4) {
                if day.isGoalMet {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tint)
                }
                Text("of \(store.unitSystem.format(millilitres: day.goalMillilitres)) goal")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            shortcuts
        }
    }

    // MARK: - Editor

    private var amountEditor: some View {
        VStack(spacing: 5) {
            Text("Drunk")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 8) {
                stepButton("minus", disabled: day.consumedMillilitres <= 0) {
                    store.adjustConsumed(by: -store.glassMillilitres, for: date)
                }

                HStack(spacing: 4) {
                    TextField("", value: amountInDisplayUnits, format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .focused($amountFocused)
                        .frame(width: 68)

                    Text(store.unitSystem.shortSuffix)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .stroke(
                            amountFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear),
                            lineWidth: 1.5
                        )
                }

                stepButton("plus", disabled: false) {
                    store.adjustConsumed(by: store.glassMillilitres, for: date)
                }
            }
        }
    }

    private func stepButton(_ symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
        .help("\(symbol == "plus" ? "Add" : "Remove") \(store.unitSystem.format(millilitres: store.glassMillilitres))")
    }

    private var shortcuts: some View {
        HStack(spacing: 8) {
            Button("Clear") {
                store.setConsumed(0, for: date)
            }
            .disabled(day.consumedMillilitres <= 0)

            Button("Met goal") {
                store.setConsumed(day.goalMillilitres, for: date)
            }
            .disabled(day.isGoalMet)
        }
        .controlSize(.small)
        .font(.system(size: 11))
    }

    /// The consumed total in whichever unit is on display, written back in millilitres.
    private var amountInDisplayUnits: Binding<Double> {
        Binding(
            get: { store.unitSystem.fromMillilitres(day.consumedMillilitres) },
            set: { store.setConsumed(store.unitSystem.toMillilitres($0), for: date) }
        )
    }
}
