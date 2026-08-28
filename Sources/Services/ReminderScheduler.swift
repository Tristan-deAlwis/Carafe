import AppKit
import Foundation
import Observation
import UserNotifications
import os

/// Schedules the "time for some water" reminders, by whichever route is available.
///
/// **Two delivery routes, because one of them is not always available.** macOS
/// refuses to register an app with the notification service unless it carries a
/// real signing identity — an ad-hoc signature (`TeamIdentifier=not set`) is
/// rejected with "Notifications are not allowed for this application", no matter
/// where the bundle lives. Until Carafe ships with a Developer ID certificate,
/// system notifications simply cannot work, so the scheduler falls back to
/// drawing attention to the menu bar icon, which needs no entitlement at all.
///
/// The two routes share one schedule: `slots(startHour:endHour:intervalMinutes:)`.
/// When a Developer ID is added, `prepare()` starts succeeding and the app moves
/// to real notifications with no other change.
///
/// System notifications use daily `UNCalendarNotificationTrigger`s rather than a
/// repeating interval trigger: interval triggers drift against the wall clock and
/// cannot be confined to waking hours, whereas calendar triggers fire at the same
/// times every day and survive restarts.
@MainActor
@Observable
final class ReminderScheduler {
    @ObservationIgnored
    static let shared = ReminderScheduler()

    /// macOS keeps at most 64 pending requests per app. Intervals are constrained
    /// in the UI so a full day of slots stays comfortably under that.
    nonisolated static let maximumSlots = 48

    nonisolated static let categoryIdentifier = "carafe.reminder"
    nonisolated static let logGlassAction = "carafe.action.logGlass"
    nonisolated static let snoozeAction = "carafe.action.snooze"
    nonisolated static let snoozeMinutes = 15

    /// How reminders reach the user.
    enum Delivery: Equatable {
        /// System notification banners, with Log-a-glass and Snooze actions.
        case notifications
        /// The menu bar icon marks itself, because notifications were refused.
        case inApp
        case off
    }

    private(set) var delivery: Delivery = .off

    /// Set when an in-app reminder is due, cleared when the popover is opened or a
    /// drink is logged. The menu bar icon watches this.
    private(set) var isAttentionRequested = false

    @ObservationIgnored private let logger = Logger(subsystem: "com.tristandealwis.carafe", category: "Reminders")
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private var canUseNotifications = false
    @ObservationIgnored private var inAppTimer: Timer?

    private init() {}

    // MARK: - Setup

    /// Registers notification actions. Safe to call more than once.
    func registerCategories() {
        let logGlass = UNNotificationAction(
            identifier: Self.logGlassAction,
            title: "Log a glass",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: Self.snoozeAction,
            title: "Snooze \(Self.snoozeMinutes) min",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [logGlass, snooze],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// Asks for notification permission once, recording whether it is usable.
    ///
    /// A refusal here is expected on unsigned builds and is not an error worth
    /// showing as a failure — it just selects the in-app route.
    @discardableResult
    func prepare() async -> Bool {
        do {
            canUseNotifications = try await center.requestAuthorization(options: [.alert, .sound])
            logger.info("Notification authorization granted: \(self.canUseNotifications)")
        } catch {
            canUseNotifications = false
            logger.notice(
                """
                Notifications unavailable (\(error.localizedDescription, privacy: .public)); \
                falling back to menu bar reminders. This is expected without a Developer ID signature.
                """
            )
        }
        return canUseNotifications
    }

    // MARK: - Scheduling

    /// Cancels everything pending and reschedules from the store's current state.
    ///
    /// Called on launch, at the day boundary, when settings change, and when the
    /// goal is crossed in either direction.
    func refresh(for store: HydrationStore) {
        center.removeAllPendingNotificationRequests()
        inAppTimer?.invalidate()
        inAppTimer = nil

        guard store.remindersEnabled else {
            delivery = .off
            clearAttention()
            logger.debug("Reminders disabled; nothing scheduled")
            return
        }

        // Once the day's goal is met, stop nagging. The day-boundary refresh puts
        // the reminders back for tomorrow.
        guard !store.isGoalMet else {
            delivery = .off
            clearAttention()
            logger.debug("Goal met; reminders suppressed until tomorrow")
            return
        }

        let slots = Self.slots(
            startHour: store.activeStartHour,
            endHour: store.activeEndHour,
            intervalMinutes: store.reminderIntervalMinutes
        )
        guard !slots.isEmpty else {
            delivery = .off
            return
        }

        if canUseNotifications {
            delivery = .notifications
            scheduleNotifications(slots: slots, store: store)
        } else {
            delivery = .inApp
            scheduleNextInAppReminder(slots: slots, store: store)
        }
    }

    private func scheduleNotifications(slots: [Slot], store: HydrationStore) {
        for slot in slots {
            var components = DateComponents()
            components.hour = slot.hour
            components.minute = slot.minute

            let content = UNMutableNotificationContent()
            content.title = "Time for some water"
            content.body = "\(store.unitSystem.format(millilitres: store.remainingMillilitres)) left today."
            content.categoryIdentifier = Self.categoryIdentifier
            content.sound = .default
            content.interruptionLevel = .passive

            let request = UNNotificationRequest(
                identifier: "carafe.slot.\(slot.hour).\(slot.minute)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            )
            center.add(request) { [logger] error in
                if let error {
                    logger.error("Could not schedule reminder: \(error.localizedDescription)")
                }
            }
        }
        logger.debug("Scheduled \(slots.count) daily notifications")
    }

    // MARK: - In-app fallback

    /// Arms a timer for the next slot still ahead today.
    ///
    /// Only one timer is live at a time; each firing arms the next. That keeps the
    /// app from holding a dozen timers and means a settings change simply
    /// re-arms cleanly.
    private func scheduleNextInAppReminder(slots: [Slot], store: HydrationStore) {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)

        let next = slots
            .compactMap { slot -> Date? in
                calendar.date(byAdding: .init(hour: slot.hour, minute: slot.minute), to: startOfDay)
            }
            .first { $0 > now }

        guard let next else {
            logger.debug("No further in-app reminders today")
            return
        }

        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fireInAppReminder(for: store)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        inAppTimer = timer

        logger.debug("Next in-app reminder at \(next, privacy: .public)")
    }

    private func fireInAppReminder(for store: HydrationStore) {
        guard store.remindersEnabled, !store.isGoalMet else { return }

        isAttentionRequested = true
        // A quiet system sound rather than a banner. Deliberately not .beep(), which
        // reads as an error.
        NSSound(named: "Glass")?.play()

        // Arm the following slot.
        refresh(for: store)
    }

    func clearAttention() {
        isAttentionRequested = false
    }

    // MARK: - Snooze

    /// A one-off reminder `snoozeMinutes` from now, via whichever route is active.
    func snooze() {
        if canUseNotifications {
            let content = UNMutableNotificationContent()
            content.title = "Time for some water"
            content.categoryIdentifier = Self.categoryIdentifier
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "carafe.snooze.\(UUID().uuidString)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(
                    timeInterval: TimeInterval(Self.snoozeMinutes * 60),
                    repeats: false
                )
            )
            center.add(request)
        } else {
            clearAttention()
            let timer = Timer(
                timeInterval: TimeInterval(Self.snoozeMinutes * 60),
                repeats: false
            ) { [weak self] _ in
                Task { @MainActor in self?.isAttentionRequested = true }
            }
            RunLoop.main.add(timer, forMode: .common)
            inAppTimer = timer
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        inAppTimer?.invalidate()
        inAppTimer = nil
        delivery = .off
    }

    // MARK: - Slot maths

    struct Slot: Equatable, Sendable {
        let hour: Int
        let minute: Int
    }

    /// Reminder times between `startHour` (inclusive) and `endHour` (exclusive).
    ///
    /// Returns an empty list rather than looping forever if the hours are inverted
    /// or the interval is nonsensical.
    ///
    /// `nonisolated` because it is pure arithmetic over its arguments — that keeps
    /// it directly unit-testable without hopping to the main actor.
    nonisolated static func slots(startHour: Int, endHour: Int, intervalMinutes: Int) -> [Slot] {
        guard intervalMinutes > 0, endHour > startHour else { return [] }

        let start = startHour * 60
        let end = endHour * 60
        var result: [Slot] = []
        var minutes = start

        while minutes < end, result.count < maximumSlots {
            result.append(Slot(hour: minutes / 60, minute: minutes % 60))
            minutes += intervalMinutes
        }
        return result
    }
}
