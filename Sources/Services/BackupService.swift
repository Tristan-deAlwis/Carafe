import AppKit
import UniformTypeIdentifiers
import os

/// Save/open panels and Finder integration for backups.
///
/// Carafe is an `LSUIElement` app, which shapes everything here: it is never the
/// active application, so a panel presented without first calling
/// `NSApp.activate()` opens *behind* whatever the user is looking at, and appears
/// to have done nothing at all. Every entry point below activates first.
///
/// Opening a panel also dismisses the menu bar popover, since the popover closes
/// as soon as focus leaves it. That is expected — the panel is the foreground task
/// at that point — and is why each action is self-contained rather than expecting
/// to return to the popover afterwards.
@MainActor
enum BackupService {
    private static let logger = Logger(subsystem: "com.tristandealwis.carafe", category: "Backup")

    // MARK: - Reveal

    /// Opens the data folder in Finder, so backing up by hand is a drag away.
    static func revealDataFolder(for store: HydrationStore) {
        let fileURL = store.historyFileURL
        let folder = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        NSApp.activate(ignoringOtherApps: true)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            NSWorkspace.shared.open(folder)
        }
    }

    // MARK: - Export

    enum ExportFormat {
        /// Full fidelity: history plus settings. This is the one to restore from.
        case json
        /// Daily totals only, for spreadsheets.
        case csv

        var contentType: UTType { self == .json ? .json : .commaSeparatedText }
        var fileExtension: String { self == .json ? "json" : "csv" }
    }

    /// Writes a backup wherever the user chooses. Returns the URL written, if any.
    @discardableResult
    static func export(_ store: HydrationStore, as format: ExportFormat) -> URL? {
        let archive = store.makeBackupArchive()

        let data: Data
        do {
            switch format {
            case .json:
                data = try archive.jsonData()
            case .csv:
                data = Data(archive.csv().utf8)
            }
        } catch {
            present(error: "Could not prepare the backup: \(error.localizedDescription)")
            return nil
        }

        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.title = "Export Carafe Data"
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = suggestedFilename(extension: format.fileExtension)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            try data.write(to: url, options: .atomic)
            logger.info("Exported backup to \(url.lastPathComponent, privacy: .public)")
            return url
        } catch {
            present(error: "Could not write the backup: \(error.localizedDescription)")
            return nil
        }
    }

    /// `Carafe-2026-08-29.json` — sorts chronologically and needs no explanation.
    private static func suggestedFilename(extension ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Carafe-\(formatter.string(from: Date())).\(ext)"
    }

    // MARK: - Import

    /// Restores from a JSON archive, after confirming the replacement.
    ///
    /// Returns true if history was replaced.
    @discardableResult
    static func importArchive(into store: HydrationStore) -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "Restore Carafe Data"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        let archive: BackupArchive
        do {
            archive = try BackupArchive.load(from: try Data(contentsOf: url))
        } catch {
            present(error: error.localizedDescription)
            return false
        }

        // Restoring replaces everything, so make that explicit before it happens
        // rather than leaving the user to discover it.
        let confirm = NSAlert()
        confirm.messageText = "Replace all Carafe data?"
        confirm.informativeText = """
            This backup holds \(archive.days.count) \(archive.days.count == 1 ? "day" : "days") \
            of history. Restoring replaces everything currently in Carafe. This cannot be undone.
            """
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Replace")
        confirm.addButton(withTitle: "Cancel")

        guard confirm.runModal() == .alertFirstButtonReturn else { return false }

        store.restore(from: archive)
        logger.info("Restored \(archive.days.count) days from \(url.lastPathComponent, privacy: .public)")
        return true
    }

    // MARK: - Errors

    private static func present(error message: String) {
        logger.error("\(message, privacy: .public)")
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Carafe"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
