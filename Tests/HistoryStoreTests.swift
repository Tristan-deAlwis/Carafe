import XCTest

@testable import Carafe

final class HistoryStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        fileURL = TestFixtures.temporaryFileURL()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        super.tearDown()
    }

    private func write(_ raw: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try raw.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func testMissingFileLoadsAsEmpty() {
        XCTAssertEqual(HistoryStore(fileURL: fileURL).load().count, 0)
    }

    func testSaveThenLoadRoundTrips() {
        let store = HistoryStore(fileURL: fileURL)
        let day = TestFixtures.day(TestFixtures.date(2026, 8, 27), goal: 2500, consumed: 1750)

        store.save([day])
        let loaded = store.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.goalMillilitres, 2500)
        XCTAssertEqual(loaded.first?.consumedMillilitres, 1750)
        XCTAssertEqual(loaded.first?.date, day.date)
    }

    func testCorruptFileDegradesToEmptyRatherThanThrowing() throws {
        try write("{ this is not json at all ")

        // A menu bar app must not crash on a bad file; starting fresh is the contract.
        XCTAssertEqual(HistoryStore(fileURL: fileURL).load().count, 0)
    }

    func testTruncatedFileDegradesToEmpty() throws {
        try write(#"{"version":1,"days":[{"date":"2026-08-2"#)

        XCTAssertEqual(HistoryStore(fileURL: fileURL).load().count, 0)
    }

    func testFileFromANewerVersionIsIgnoredAndLeftIntact() throws {
        let raw = #"{"version":999,"days":[]}"#
        try write(raw)

        XCTAssertEqual(HistoryStore(fileURL: fileURL).load().count, 0)
        // Crucially, the file is not overwritten, so downgrading does not destroy history.
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), raw)
    }

    func testLoadReturnsDaysSortedAscending() {
        let store = HistoryStore(fileURL: fileURL)
        store.save([
            TestFixtures.day(TestFixtures.date(2026, 8, 27), consumed: 100),
            TestFixtures.day(TestFixtures.date(2026, 8, 25), consumed: 100),
            TestFixtures.day(TestFixtures.date(2026, 8, 26), consumed: 100),
        ])

        let dates = store.load().map(\.date)

        XCTAssertEqual(dates, dates.sorted())
    }

    func testSavePrunesToTheRetentionBound() {
        let store = HistoryStore(fileURL: fileURL)
        let calendar = TestFixtures.calendar
        let start = TestFixtures.date(2024, 1, 1)
        let many = (0..<(HistoryStore.maximumRetainedDays + 50)).map { offset in
            TestFixtures.day(calendar.date(byAdding: .day, value: offset, to: start)!, consumed: 2000)
        }

        store.save(many)
        let loaded = store.load()

        XCTAssertEqual(loaded.count, HistoryStore.maximumRetainedDays)
        // Pruning drops the oldest, keeping the most recent window.
        XCTAssertEqual(loaded.last?.date, many.last?.date)
    }

    func testSaveCreatesTheContainingDirectory() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path))

        HistoryStore(fileURL: fileURL).save([TestFixtures.day(TestFixtures.date(2026, 8, 27), consumed: 500)])

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testDefaultLocationIsOutsideASandboxContainer() {
        // The app is not sandboxed, so history must land at the documented path.
        let url = HistoryStore.defaultFileURL()

        XCTAssertEqual(url.lastPathComponent, "history.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Carafe")
        XCTAssertFalse(url.path.contains("/Containers/"))
    }
}
