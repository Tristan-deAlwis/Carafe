import Foundation

/// A complete, portable snapshot of everything Carafe knows about you.
///
/// The on-disk history at `~/Library/Application Support/Carafe/history.json` is
/// already plain JSON, but it is only half the picture — settings live in
/// `UserDefaults`, inside a binary plist Carafe does not own. An archive puts both
/// in one self-describing text file, so a backup is a single artefact you can copy
/// to a USB stick, commit to a private git repo, or read in any language.
///
/// Design rules, in service of that:
///
/// - **Plain JSON, pretty-printed, keys sorted.** Diffable in git and readable in
///   any text editor. No compression, no binary plists, no proprietary container.
/// - **ISO 8601 dates.** Unambiguous across locales and timezones.
/// - **Self-describing.** `format` and `version` are the first things in the file,
///   so a reader can tell what it is holding without guessing.
/// - **Additive evolution.** New fields must be optional so that older archives
///   keep decoding. `version` only rises for a genuinely breaking change.
struct BackupArchive: Codable, Equatable, Sendable {
    /// Identifies the file even after it has been renamed.
    static let formatIdentifier = "carafe.backup"
    static let currentVersion = 1

    var format: String
    var version: Int
    var exportedAt: Date
    /// The Carafe version that wrote the file. Informational only.
    var appVersion: String?
    var settings: Settings
    var days: [DayLog]

    /// Everything configurable, mirroring `HydrationStore`'s stored settings.
    ///
    /// All optional so an archive written by a future version — or hand-edited to
    /// drop a field — still restores what it does carry.
    struct Settings: Codable, Equatable, Sendable {
        var goalMillilitres: Double?
        var glassMillilitres: Double?
        var unitSystem: UnitSystem?
        var remindersEnabled: Bool?
        var reminderIntervalMinutes: Int?
        var activeStartHour: Int?
        var activeEndHour: Int?
    }

    // MARK: - Coding

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func jsonData() throws -> Data {
        try Self.makeEncoder().encode(self)
    }

    enum LoadError: LocalizedError, Equatable {
        case notACarafeBackup
        case unsupportedVersion(Int)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .notACarafeBackup:
                "That file is not a Carafe backup."
            case .unsupportedVersion(let version):
                "This backup was written by a newer version of Carafe (format \(version))."
            case .unreadable(let detail):
                "The backup could not be read: \(detail)"
            }
        }
    }

    /// Decodes an archive, rejecting files that are valid JSON but not ours.
    ///
    /// Checking `format` matters: without it, any JSON object whose fields happen to
    /// be absent would decode into an empty archive and silently wipe the history it
    /// was meant to restore.
    static func load(from data: Data) throws -> BackupArchive {
        // Check the format tag before attempting a full decode. Otherwise a JSON
        // file from some other app fails on a missing required field and reports
        // "the data is missing", when what the user needs to hear is that they
        // picked the wrong file.
        if let json = try? JSONSerialization.jsonObject(with: data) {
            guard let object = json as? [String: Any],
                  object["format"] as? String == formatIdentifier
            else { throw LoadError.notACarafeBackup }
        }

        let archive: BackupArchive
        do {
            archive = try makeDecoder().decode(BackupArchive.self, from: data)
        } catch {
            throw LoadError.unreadable(error.localizedDescription)
        }
        guard archive.format == formatIdentifier else { throw LoadError.notACarafeBackup }
        guard archive.version <= currentVersion else {
            throw LoadError.unsupportedVersion(archive.version)
        }
        return archive
    }

    // MARK: - CSV

    /// The same history as CSV, for spreadsheets and one-line shell pipelines.
    ///
    /// Export-only and lossy by design: it carries the daily totals, not the
    /// individual drink entries, because a rectangular table is what makes it useful
    /// in a spreadsheet. Use the JSON archive for a full backup.
    func csv() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        var lines = ["date,goal_ml,consumed_ml,remaining_ml,goal_met"]
        for day in days.sorted(by: { $0.date < $1.date }) {
            let fields = [
                formatter.string(from: day.date),
                Self.number(day.goalMillilitres),
                Self.number(day.consumedMillilitres),
                Self.number(day.remainingMillilitres),
                day.isGoalMet ? "true" : "false",
            ]
            lines.append(fields.joined(separator: ","))
        }
        // Trailing newline: POSIX text files end with one, and its absence upsets
        // `wc -l` and some spreadsheet importers.
        return lines.joined(separator: "\n") + "\n"
    }

    /// Formats a volume without a locale's thousands separators or decimal comma,
    /// either of which would corrupt a CSV field.
    private static func number(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.2f", value)
    }
}
