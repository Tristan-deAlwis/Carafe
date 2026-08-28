import SwiftUI

/// Settings, shown inline inside the popover.
///
/// Laid out as compact label/control rows rather than a `Form`, whose grouped
/// styling assumes a settings *window* and looks heavy at popover width.
struct SettingsView: View {
    @Environment(HydrationStore.self) private var store

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginProblem: String?

    /// Kept modest so a day of slots stays well under the system's 64-request limit.
    private let intervalChoices = [30, 45, 60, 90, 120, 180]

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 0) {
            section("Hydration") {
                row("Daily goal") {
                    Picker("", selection: $store.goalMillilitres) {
                        ForEach(goalChoices, id: \.self) { amount in
                            Text(store.unitSystem.format(millilitres: amount)).tag(amount)
                        }
                    }
                    .labelsHidden()
                }
                row("Glass size") {
                    Picker("", selection: $store.glassMillilitres) {
                        ForEach(glassChoices, id: \.self) { amount in
                            Text(store.unitSystem.format(millilitres: amount)).tag(amount)
                        }
                    }
                    .labelsHidden()
                }
                row("Units") {
                    Picker("", selection: $store.unitSystem) {
                        Text("ml").tag(UnitSystem.metric)
                        Text("fl oz").tag(UnitSystem.us)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 110)
                }
            }

            Divider().padding(.vertical, 10)

            section("Reminders") {
                row("Remind me") {
                    Toggle("", isOn: $store.remindersEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                if store.remindersEnabled {
                    row("Every") {
                        Picker("", selection: $store.reminderIntervalMinutes) {
                            ForEach(intervalChoices, id: \.self) { minutes in
                                Text(intervalLabel(minutes)).tag(minutes)
                            }
                        }
                        .labelsHidden()
                    }
                    row("Between") {
                        HStack(spacing: 4) {
                            hourPicker(selection: $store.activeStartHour, range: 0...22)
                            Text("and").foregroundStyle(.secondary).font(.system(size: 11))
                            hourPicker(selection: $store.activeEndHour, range: (store.activeStartHour + 1)...23)
                        }
                    }

                    if ReminderScheduler.shared.delivery == .inApp {
                        note(
                            "System notifications are unavailable in this build, so Carafe "
                                + "will mark its menu bar icon instead.",
                            isWarning: false
                        )
                    }
                }
            }

            Divider().padding(.vertical, 10)

            section("General") {
                row("Launch at login") {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                if let launchAtLoginProblem {
                    note(launchAtLoginProblem, isWarning: true)
                }
            }

            Divider().padding(.vertical, 10)

            HStack {
                Text("Carafe \(appVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .font(.system(size: 12))
        .onChange(of: launchAtLogin) { _, enabled in
            applyLaunchAtLogin(enabled)
        }
        .onChange(of: store.remindersEnabled) { _, enabled in
            Task { await updateReminders(enabled: enabled) }
        }
        .onChange(of: store.reminderIntervalMinutes) { _, _ in
            ReminderScheduler.shared.refresh(for: store)
        }
        .onChange(of: store.activeStartHour) { _, _ in
            // Keep the window valid if the start is dragged past the end.
            if store.activeEndHour <= store.activeStartHour {
                store.activeEndHour = min(23, store.activeStartHour + 1)
            }
            ReminderScheduler.shared.refresh(for: store)
        }
        .onChange(of: store.activeEndHour) { _, _ in
            ReminderScheduler.shared.refresh(for: store)
        }
        .onChange(of: store.goalMillilitres) { _, _ in
            ReminderScheduler.shared.refresh(for: store)
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func row(_ label: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 8)
            control()
        }
    }

    private func note(_ text: String, isWarning: Bool) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(isWarning ? Color.orange : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func hourPicker(selection: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Picker("", selection: selection) {
            ForEach(Array(range), id: \.self) { hour in
                Text(hourLabel(hour)).tag(hour)
            }
        }
        .labelsHidden()
        .frame(width: 78)
    }

    // MARK: - Choices

    /// Presets for the current unit system, plus whatever is currently set if it is
    /// not one of them — otherwise a value carried over from the other unit system
    /// would have no matching tag and the picker would render blank.
    private var goalChoices: [Double] {
        merge(store.unitSystem.goalPresetsMillilitres, with: store.goalMillilitres)
    }

    private var glassChoices: [Double] {
        merge(store.unitSystem.glassPresetsMillilitres, with: store.glassMillilitres)
    }

    private func merge(_ presets: [Double], with current: Double) -> [Double] {
        presets.contains(where: { abs($0 - current) < 0.5 })
            ? presets
            : (presets + [current]).sorted()
    }

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = Double(minutes) / 60
        let formatted = hours == hours.rounded()
            ? String(Int(hours))
            : hours.formatted(.number.precision(.fractionLength(1)))
        return "\(formatted) hr"
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        guard let date = Calendar.current.date(from: components) else { return "\(hour):00" }
        return date.formatted(.dateTime.hour().minute())
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    // MARK: - Actions

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginProblem = LaunchAtLogin.requiresApproval
                ? "Approve Carafe in System Settings › General › Login Items."
                : nil
        } catch {
            // Reflect reality rather than leaving the switch on a lie.
            launchAtLogin = LaunchAtLogin.isEnabled
            launchAtLoginProblem = "Could not set launch at login: \(error.localizedDescription)"
        }
    }

    private func updateReminders(enabled: Bool) async {
        if enabled {
            // Re-checks the delivery route. A refusal is not fatal — the scheduler
            // falls back to marking the menu bar icon.
            await ReminderScheduler.shared.prepare()
        }
        ReminderScheduler.shared.refresh(for: store)
    }
}
