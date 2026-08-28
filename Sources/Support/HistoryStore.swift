import Foundation
import os

/// JSON persistence for hydration history.
///
/// Deliberately synchronous and dependency-free: the file holds at most a few
/// hundred small records, so a blocking read at launch costs well under a
/// millisecond. Writes are dispatched off the main actor by `HydrationStore`.
///
/// The store never throws on load. A missing file is a first launch; a corrupt
/// file is a bug or a half-written disk, and in both cases starting fresh beats
/// crashing a menu bar app the user cannot easily see the logs for.
struct HistoryStore: Sendable {
    /// Bump when the on-disk shape changes incompatibly, and migrate in `decode`.
    static let currentVersion = 1

    /// Retention bound. Roughly 14 months — enough for a year-long streak view
    /// while keeping the file trivially small.
    static let maximumRetainedDays = 400

    private static let logger = Logger(subsystem: "com.tristandealwis.carafe", category: "HistoryStore")

    let fileURL: URL

    /// The default location: `~/Library/Application Support/Carafe/history.json`.
    ///
    /// The app is not sandboxed, so this is the real path rather than a container.
    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("Carafe", isDirectory: true)
            .appendingPathComponent("history.json", isDirectory: false)
    }

    init(fileURL: URL = HistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    // MARK: - Envelope

    private struct Envelope: Codable {
        var version: Int
        var days: [DayLog]
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    // MARK: - Load / save

    /// Reads history from disk, returning an empty array if the file is absent or unreadable.
    func load() -> [DayLog] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let envelope = try Self.makeDecoder().decode(Envelope.self, from: data)
            guard envelope.version <= Self.currentVersion else {
                // Written by a newer build. Refuse to interpret it, and leave the
                // file alone so downgrading does not destroy the user's history.
                Self.logger.warning("history.json version \(envelope.version) is newer than \(Self.currentVersion); ignoring")
                return []
            }
            return envelope.days.sorted { $0.date < $1.date }
        } catch {
            Self.logger.error("Could not read history.json, starting fresh: \(error.localizedDescription)")
            return []
        }
    }

    /// Writes history atomically, pruning to `maximumRetainedDays`.
    ///
    /// Atomic replacement means an interrupted write leaves the previous file intact
    /// rather than a truncated one.
    func save(_ days: [DayLog]) {
        let pruned = Array(days.sorted { $0.date < $1.date }.suffix(Self.maximumRetainedDays))
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try Self.makeEncoder().encode(Envelope(version: Self.currentVersion, days: pruned))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Self.logger.error("Could not write history.json: \(error.localizedDescription)")
        }
    }
}
