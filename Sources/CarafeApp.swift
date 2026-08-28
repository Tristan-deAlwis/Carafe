import SwiftUI

@main
struct CarafeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// Observed so the icon can badge itself when the in-app reminder fallback fires.
    private var scheduler = ReminderScheduler.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView()
                .environment(appDelegate.store)
        } label: {
            // A pre-rendered template image rather than a SwiftUI shape, so AppKit
            // owns the light/dark and selected-state appearances. See MenuBarIcon.
            Image(nsImage: MenuBarIcon.standard(attention: scheduler.isAttentionRequested))
        }
        .menuBarExtraStyle(.window)
    }
}
