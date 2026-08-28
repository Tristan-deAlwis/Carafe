import XCTest

@testable import Carafe

/// The backup format is a promise to the user that their data stays theirs, so
/// these tests pin the things that promise depends on: it is plain readable JSON,
/// it round-trips, and it refuses to silently destroy history when handed a file
/// it does not understand.
@MainActor
final class BackupArchiveTests: XCTestCase {
    private var clock: MutableClock!
    private var fileURL: URL!
    private var calendar: Calendar!

    private let today = TestFixtures.date(2026, 8, 28)

    override func setUp() {
        super.setUp()
        calendar = TestFixtures.calendar
        clock = MutableClock(TestFixtures.date(2026, 8, 28, hour: 9))
        fileURL = TestFixtures.temporaryFileURL()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        super.tearDown()
    }

    private func daysAgo(_ count: Int) -> Date {
        calendar.date(byAdding: .day, value: -count, to: today)!
    }

    private func makeStore(seeding days: [DayLog] = []) -> HydrationStore {
        if !days.isEmpty {
            HistoryStore(fileURL: fileURL).save(days)
        }
        return HydrationStore(
            historyStore: HistoryStore(fileURL: fileURL),
            defaults: TestFixtures.isolatedDefaults(),
            calendar: calendar,
            now: clock.provider
        )
    }

    /// A store backed by its own file and defaults, sharing nothing with `makeStore`.
    ///
    /// Stands in for a different machine. Using `makeStore()` here would silently
    /// reload the seeded history from the shared file and the store would not be
    /// empty at all.
    private func makeIndependentStore() -> HydrationStore {
        HydrationStore(
            historyStore: HistoryStore(fileURL: TestFixtures.temporaryFileURL()),
            defaults: TestFixtures.isolatedDefaults(),
            calendar: calendar,
            now: clock.provider
        )
    }

    /// A store with a few days of history and non-default settings.
    private func populatedStore() -> HydrationStore {
        let store = makeStore(seeding: [
            TestFixtures.day(daysAgo(2), goal: 2000, consumed: 2000),
            TestFixtures.day(daysAgo(1), goal: 2000, consumed: 1250),
        ])
        store.goalMillilitres = 2500
        store.glassMillilitres = 330
        store.unitSystem = .us
        store.reminderIntervalMinutes = 45
        store.activeStartHour = 7
        store.activeEndHour = 22
        store.remindersEnabled = false
        store.log(millilitres: 500)
        return store
    }

    // MARK: - The format is open

    func testArchiveIsHumanReadableJSON() throws {
        let data = try populatedStore().makeBackupArchive().jsonData()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        // Readable in any text editor: indented, not one dense line.
        XCTAssertTrue(text.contains("\n"))
        XCTAssertTrue(text.contains("  "))
        // Self-describing, so a reader knows what it has without guessing.
        XCTAssertTrue(text.contains("\"format\" : \"carafe.backup\""))
        XCTAssertTrue(text.contains("\"version\" : 1"))
        // ISO 8601 dates rather than opaque numeric timestamps.
        XCTAssertTrue(text.contains("2026-08-2"))
    }

    func testArchiveIsParseableByAnyJSONReader() throws {
        let data = try populatedStore().makeBackupArchive().jsonData()

        // Decoded with Foundation's generic parser rather than our own Codable
        // types, standing in for jq, Python, or anything else the user reaches for.
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let root = try XCTUnwrap(object)

        XCTAssertEqual(root["format"] as? String, "carafe.backup")
        XCTAssertEqual((root["days"] as? [Any])?.count, 3)
        XCTAssertNotNil(root["settings"] as? [String: Any])
    }

    func testKeysAreSortedSoBackupsDiffCleanly() throws {
        let data = try populatedStore().makeBackupArchive().jsonData()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        let format = try XCTUnwrap(text.range(of: "\"format\""))
        let version = try XCTUnwrap(text.range(of: "\"version\""))
        // Sorted keys keep successive backups diffable in git.
        XCTAssertTrue(format.lowerBound < version.lowerBound)
    }

    // MARK: - Round trip

    func testArchiveRoundTripsThroughJSON() throws {
        let archive = populatedStore().makeBackupArchive()

        let restored = try BackupArchive.load(from: archive.jsonData())

        XCTAssertEqual(restored, archive)
    }

    func testRestoreBringsBackHistoryAndSettings() throws {
        let data = try populatedStore().makeBackupArchive().jsonData()

        // A completely separate store, as if on a new machine.
        let fresh = makeIndependentStore()
        fresh.restore(from: try BackupArchive.load(from: data))

        XCTAssertEqual(fresh.goalMillilitres, 2500)
        XCTAssertEqual(fresh.glassMillilitres, 330)
        XCTAssertEqual(fresh.unitSystem, .us)
        XCTAssertEqual(fresh.reminderIntervalMinutes, 45)
        XCTAssertEqual(fresh.activeStartHour, 7)
        XCTAssertEqual(fresh.activeEndHour, 22)
        XCTAssertFalse(fresh.remindersEnabled)
        XCTAssertEqual(fresh.consumedMillilitres, 500)
        XCTAssertEqual(fresh.log(for: daysAgo(1))?.consumedMillilitres, 1250)
    }

    func testStreakRecomputesFromRestoredHistory() throws {
        let source = makeStore(seeding: [
            TestFixtures.day(daysAgo(3), goal: 2000, consumed: 2000),
            TestFixtures.day(daysAgo(2), goal: 2000, consumed: 2100),
            TestFixtures.day(daysAgo(1), goal: 2000, consumed: 2000),
        ])
        let data = try source.makeBackupArchive().jsonData()

        let fresh = makeIndependentStore()
        XCTAssertEqual(fresh.currentStreak, 0, "nothing to count before the restore")

        fresh.restore(from: try BackupArchive.load(from: data))

        // Derived state is not stored in the archive — it has to fall out of the
        // restored day records.
        XCTAssertEqual(fresh.currentStreak, 3)
    }

    func testRestoringAHistoryWithAGapYieldsNoStreak() throws {
        // Yesterday fell short, so nothing earlier counts however good it was.
        let source = makeStore(seeding: [
            TestFixtures.day(daysAgo(2), goal: 2000, consumed: 2000),
            TestFixtures.day(daysAgo(1), goal: 2000, consumed: 1250),
        ])
        let data = try source.makeBackupArchive().jsonData()

        let fresh = makeIndependentStore()
        fresh.restore(from: try BackupArchive.load(from: data))

        XCTAssertEqual(fresh.currentStreak, 0)
    }

    func testRestoreSurvivesARestart() throws {
        let data = try populatedStore().makeBackupArchive().jsonData()
        let target = TestFixtures.temporaryFileURL()
        let defaults = TestFixtures.isolatedDefaults()

        let first = HydrationStore(
            historyStore: HistoryStore(fileURL: target),
            defaults: defaults,
            calendar: calendar,
            now: clock.provider
        )
        first.restore(from: try BackupArchive.load(from: data))

        // restore() flushes immediately rather than debouncing, so a quit right
        // after a restore cannot lose it.
        let reopened = HydrationStore(
            historyStore: HistoryStore(fileURL: target),
            defaults: defaults,
            calendar: calendar,
            now: clock.provider
        )
        XCTAssertEqual(reopened.log(for: daysAgo(1))?.consumedMillilitres, 1250)
    }

    func testRestoreCreatesTodayWhenTheArchiveIsOld() throws {
        let store = makeStore(seeding: [TestFixtures.day(daysAgo(30), consumed: 1000)])
        var archive = store.makeBackupArchive()
        archive.days = [TestFixtures.day(daysAgo(30), consumed: 1000)]

        let fresh = makeStore()
        fresh.restore(from: archive)

        XCTAssertNotNil(fresh.log(for: today), "today must exist again after restoring old data")
        XCTAssertEqual(fresh.consumedMillilitres, 0)
    }

    func testRestoreLeavesSettingsAloneWhenTheArchiveOmitsThem() throws {
        let store = makeStore()
        store.goalMillilitres = 2500
        store.glassMillilitres = 330

        var archive = store.makeBackupArchive()
        archive.settings = BackupArchive.Settings()  // every field nil
        store.restore(from: archive)

        XCTAssertEqual(store.goalMillilitres, 2500, "a missing field must not reset to a default")
        XCTAssertEqual(store.glassMillilitres, 330)
    }

    // MARK: - Rejecting bad input

    func testForeignJSONIsRejectedRatherThanWipingHistory() {
        // Valid JSON, every field absent. Without the format check this would decode
        // into an empty archive and destroy the history it was meant to restore.
        let data = Data(#"{"hello":"world"}"#.utf8)

        XCTAssertThrowsError(try BackupArchive.load(from: data)) { error in
            XCTAssertEqual(error as? BackupArchive.LoadError, .notACarafeBackup)
        }
    }

    func testWrongFormatIdentifierIsRejected() throws {
        var archive = populatedStore().makeBackupArchive()
        archive.format = "some.other.app"

        XCTAssertThrowsError(try BackupArchive.load(from: archive.jsonData())) { error in
            XCTAssertEqual(error as? BackupArchive.LoadError, .notACarafeBackup)
        }
    }

    func testNewerFormatVersionIsRejected() throws {
        var archive = populatedStore().makeBackupArchive()
        archive.version = BackupArchive.currentVersion + 1

        XCTAssertThrowsError(try BackupArchive.load(from: archive.jsonData())) { error in
            XCTAssertEqual(
                error as? BackupArchive.LoadError,
                .unsupportedVersion(BackupArchive.currentVersion + 1)
            )
        }
    }

    func testMalformedJSONIsRejected() {
        XCTAssertThrowsError(try BackupArchive.load(from: Data("{ not json".utf8)))
    }

    func testEveryRejectionHasAReadableMessage() {
        let errors: [BackupArchive.LoadError] = [
            .notACarafeBackup,
            .unsupportedVersion(9),
            .unreadable("detail"),
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }

    // MARK: - CSV

    func testCSVHasAHeaderAndOneRowPerDay() {
        let csv = populatedStore().makeBackupArchive().csv()
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.isEmpty }

        XCTAssertEqual(lines.first, "date,goal_ml,consumed_ml,remaining_ml,goal_met")
        XCTAssertEqual(lines.count, 4, "header plus three days")
        XCTAssertTrue(csv.hasSuffix("\n"), "POSIX text files end with a newline")
    }

    func testCSVRowsAreChronological() {
        let csv = populatedStore().makeBackupArchive().csv()
        let dates = csv.split(separator: "\n").dropFirst().map { $0.split(separator: ",")[0] }

        XCTAssertEqual(dates, dates.sorted())
    }

    func testCSVNumbersAreUnformattedSoFieldsCannotSplit() {
        let store = makeStore()
        store.goalMillilitres = 2000
        store.log(millilitres: 1500)

        let row = store.makeBackupArchive().csv()
            .split(separator: "\n")
            .last!

        // A locale-formatted "1,500" would break the row into an extra column.
        XCTAssertFalse(row.contains("1,500"))
        XCTAssertTrue(row.contains("1500"))
        XCTAssertEqual(row.split(separator: ",", omittingEmptySubsequences: false).count, 5)
    }

    func testCSVReportsGoalMetPerDay() {
        let csv = makeStore(seeding: [
            TestFixtures.day(daysAgo(2), goal: 2000, consumed: 2000),
            TestFixtures.day(daysAgo(1), goal: 2000, consumed: 900),
        ]).makeBackupArchive().csv()

        let rows = csv.split(separator: "\n").dropFirst()
        XCTAssertTrue(rows.first!.hasSuffix("true"))
        XCTAssertTrue(rows.dropFirst().first!.hasSuffix("false"))
    }

    // MARK: - Discoverability

    func testHistoryFileURLPointsAtTheDocumentedLocation() {
        XCTAssertEqual(makeStore().historyFileURL, fileURL)
        // And the real one is where the README says it is.
        XCTAssertTrue(HistoryStore.defaultFileURL().path.hasSuffix("Carafe/history.json"))
    }
}
