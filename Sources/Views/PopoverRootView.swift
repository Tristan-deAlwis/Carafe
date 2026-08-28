import SwiftUI

/// The panel shown when the menu bar icon is clicked.
///
/// Settings are presented inline rather than in a separate `Settings` scene. An
/// `LSUIElement` app has no Dock icon or app menu to open a preferences window
/// from, and activating one from a menu bar popover means fighting focus; swapping
/// the panel's contents keeps everything in the one surface the user already has open.
struct PopoverRootView: View {
    @Environment(HydrationStore.self) private var store

    @State private var page: Page = .main
    /// Drives the water ripple. False whenever the popover is not on screen, so an
    /// idle menu bar app costs no CPU.
    @State private var isVisible = false

    private enum Page: Equatable {
        case main
        case settings
        /// Editing one day's total, identified by its start-of-day date.
        case day(Date)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                switch page {
                case .main: main
                case .settings: SettingsView()
                case .day(let date): DayEditorView(date: date)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 288)
        .onAppear {
            // Opening the popover is the third rollover trigger, alongside the
            // midnight timer and the wake notification in AppDelegate.
            store.rollOverIfNeeded()
            isVisible = true
            // Opening the popover acknowledges any in-app reminder badge.
            ReminderScheduler.shared.clearAttention()
        }
        .onDisappear { isVisible = false }
        .onChange(of: store.isGoalMet) { _, _ in
            // Crossing the goal in either direction suppresses or restores reminders.
            ReminderScheduler.shared.refresh(for: store)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            if page != .main {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { page = .main }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .help("Back")
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if page == .main {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { page = .settings }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var title: String {
        switch page {
        case .main:
            "Carafe"
        case .settings:
            "Settings"
        case .day(let date):
            // "Today" beats a date the user has to decode, and a weekday alone is
            // ambiguous once you go back a week.
            Calendar.current.isDateInToday(date)
                ? "Today"
                : date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        }
    }

    // MARK: - Main page

    private var main: some View {
        VStack(spacing: 14) {
            CarafeGaugeView(
                fillFraction: store.fillFraction,
                goalMillilitres: store.today.goalMillilitres,
                unitSystem: store.unitSystem,
                animateWaves: isVisible
            )
            .frame(width: 136, height: 190)

            readout

            QuickAddView()

            Divider()

            HistoryStripView { day in
                withAnimation(.snappy(duration: 0.2)) { page = .day(day.date) }
            }
        }
    }

    private var readout: some View {
        VStack(spacing: 2) {
            if store.isGoalMet {
                Text("Goal reached")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tint)
            } else {
                Text(store.unitSystem.format(millilitres: store.remainingMillilitres))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.4), value: store.remainingMillilitres)
            }

            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        let goal = store.unitSystem.format(millilitres: store.today.goalMillilitres)
        if store.isGoalMet {
            return "\(store.unitSystem.format(millilitres: store.consumedMillilitres)) of \(goal) today"
        }
        return "left of \(goal) today"
    }
}
