import AppKit
import SwiftUI
import UserNotifications

/// Owns the app's lifetime-scoped objects and the events SwiftUI scenes cannot see.
///
/// A `MenuBarExtra`'s content view is created and destroyed as the popover opens
/// and closes, so anything that must keep running while the popover is shut — the
/// midnight rollover, wake handling, reminder scheduling — has to live here rather
/// than in a view.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = HydrationStore()

    private var midnightTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        scheduleMidnightRollover()
        observeWake()

        UNUserNotificationCenter.current().delegate = self
        ReminderScheduler.shared.registerCategories()

        Task { @MainActor in
            // Selects the delivery route: real notifications when the build carries
            // a signing identity, the menu bar fallback otherwise.
            await ReminderScheduler.shared.prepare()
            ReminderScheduler.shared.refresh(for: store)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Logging debounces its write by a few hundred milliseconds; quitting inside
        // that window must not lose the last drink.
        store.flushPendingSave()

        midnightTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    // No deinit unregistering the wake observer: the app delegate lives for the
    // whole process lifetime, and a nonisolated deinit cannot touch main-actor
    // state under Swift 6 anyway. Teardown happens in applicationWillTerminate.

    // MARK: - Day rollover

    /// Rolls the day over at local midnight.
    ///
    /// This is one of three triggers, because no single one is sufficient: a timer
    /// does not fire while the machine is asleep, wake does not fire if the machine
    /// stays awake overnight, and opening the popover only helps once you look at it.
    private func scheduleMidnightRollover() {
        midnightTimer?.invalidate()

        let calendar = Calendar.current
        let now = Date()
        guard let nextMidnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else { return }

        // A second of slack, so the timer cannot fire a hair before the boundary and
        // compute the same day again.
        let interval = nextMidnight.timeIntervalSince(now) + 1

        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleDayBoundary()
            }
        }
        // Common mode keeps it firing while menus are tracking.
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }

    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Sleeping through midnight leaves the timer unfired and stale.
                self?.handleDayBoundary()
            }
        }
    }

    private func handleDayBoundary() {
        store.rollOverIfNeeded()
        scheduleMidnightRollover()
        // A new day means the goal is unmet again, so reminders come back.
        ReminderScheduler.shared.refresh(for: store)
    }
}

// MARK: - Notification actions

/// `UNUserNotificationCenterDelegate` is not main-actor isolated and its arguments
/// are not `Sendable`, so these methods stay `nonisolated`. Each one pulls out the
/// plain `String` it needs and hops to the main actor with that, rather than trying
/// to carry a `UNNotificationResponse` across isolation — which is what the
/// compiler is right to refuse.
extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show reminders even while Carafe is the active app.
    ///
    /// Without this, a reminder arriving while the popover is open is swallowed
    /// silently, which reads as the feature being broken.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        await handle(action: action)
    }

    private func handle(action: String) {
        switch action {
        case ReminderScheduler.logGlassAction:
            // Logging straight from the banner, without opening the popover, is the
            // whole point of having an action here.
            store.rollOverIfNeeded()
            store.logGlass()
            ReminderScheduler.shared.refresh(for: store)

        case ReminderScheduler.snoozeAction:
            ReminderScheduler.shared.snooze()

        default:
            break
        }
    }
}
