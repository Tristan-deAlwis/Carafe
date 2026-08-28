import Foundation
import ServiceManagement
import os

/// Launch-at-login via `SMAppService`, the supported mechanism since macOS 13.
///
/// Registration is genuinely fallible — an unsigned or ad-hoc-signed build, or one
/// running from a quarantined location, can be refused by the system. Callers get
/// the error so the UI can say so, rather than silently leaving a toggle on that
/// will not survive a reboot.
@MainActor
enum LaunchAtLogin {
    private static let logger = Logger(subsystem: "com.tristandealwis.carafe", category: "LaunchAtLogin")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when the user has to approve the login item in System Settings.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        logger.info("Launch at login set to \(enabled)")
    }

    /// Opens the Login Items pane, for when registration needs user approval.
    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
