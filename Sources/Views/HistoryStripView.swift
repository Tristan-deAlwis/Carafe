import SwiftUI

/// A seven-day bar strip with the current streak.
///
/// The bars show *progress* — taller means you drank more — which is the opposite
/// sense to the carafe above. That inversion is deliberate: a carafe draining is
/// the natural metaphor for what is left today, while a row of history bars is
/// only legible if a good day is a tall bar.
struct HistoryStripView: View {
    /// Called when a day is clicked, so the caller can open the editor for it.
    var onSelect: ((DayLog) -> Void)?

    @Environment(HydrationStore.self) private var store

    private let barHeight: CGFloat = 26

    var body: some View {
        VStack(spacing: 7) {
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(store.recentDays(7)) { day in
                    Button {
                        onSelect?(day)
                    } label: {
                        bar(for: day)
                    }
                    .buttonStyle(.plain)
                    .disabled(onSelect == nil)
                    .help("Edit \(dayName(day))")
                }
            }
            .frame(height: barHeight)

            HStack {
                Text("Last 7 days")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                if store.currentStreak > 0 {
                    Label(streakText, systemImage: "flame.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Current streak: \(streakText)")
                }
            }
        }
    }

    private func bar(for day: DayLog) -> some View {
        let progress = day.progressFraction
        let isToday = Calendar.current.isDateInToday(day.date)

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(day.isGoalMet ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.45)))
                // A day with nothing logged still gets a sliver, so the strip reads as
                // seven days rather than appearing to have gaps.
                .frame(height: max(2, barHeight * progress))
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            if isToday {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
                    .frame(height: barHeight)
            }
        }
        // The whole column is the target, not just the drawn bar — a day with
        // nothing logged is only two points tall and would be unclickable otherwise.
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel(for: day))
        .accessibilityHint("Edit the amount drunk")
    }

    private var streakText: String {
        store.currentStreak == 1 ? "1 day" : "\(store.currentStreak) days"
    }

    private func dayName(_ day: DayLog) -> String {
        Calendar.current.isDateInToday(day.date)
            ? "today"
            : day.date.formatted(.dateTime.weekday(.wide))
    }

    private func accessibilityLabel(for day: DayLog) -> String {
        let amount = store.unitSystem.format(millilitres: day.consumedMillilitres)
        return "\(dayName(day)): \(amount)\(day.isGoalMet ? ", goal met" : "")"
    }
}
