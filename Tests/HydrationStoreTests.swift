import XCTest

@testable import Carafe

@MainActor
final class HydrationStoreTests: XCTestCase {
    private var clock: MutableClock!
    private var fileURL: URL!
    private var defaults: UserDefaults!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = TestFixtures.calendar
        clock = MutableClock(TestFixtures.date(2026, 8, 28, hour: 9))
        fileURL = TestFixtures.temporaryFileURL()
        defaults = TestFixtures.isolatedDefaults()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        super.tearDown()
    }

    private func makeStore(seeding days: [DayLog] = []) -> HydrationStore {
        if !days.isEmpty {
            HistoryStore(fileURL: fileURL).save(days)
        }
        return HydrationStore(
            historyStore: HistoryStore(fileURL: fileURL),
            defaults: defaults,
            calendar: calendar,
            now: clock.provider
        )
    }

    // MARK: - Defaults and the drain model

    func testFreshStoreStartsWithAFullCarafe() {
        let store = makeStore()

        XCTAssertEqual(store.goalMillilitres, 2000)
        XCTAssertEqual(store.consumedMillilitres, 0)
        XCTAssertEqual(store.remainingMillilitres, 2000)
        // Carafe drains: untouched means full.
        XCTAssertEqual(store.fillFraction, 1.0)
        XCTAssertFalse(store.isGoalMet)
    }

    func testLoggingDrainsTheCarafe() {
        let store = makeStore()

        store.log(millilitres: 500)

        XCTAssertEqual(store.consumedMillilitres, 500)
        XCTAssertEqual(store.remainingMillilitres, 1500)
        XCTAssertEqual(store.fillFraction, 0.75)
    }

    func testLogGlassUsesConfiguredGlassSize() {
        let store = makeStore()
        store.glassMillilitres = 330

        store.logGlass()

        XCTAssertEqual(store.consumedMillilitres, 330)
    }

    func testOverdrinkingClampsRatherThanGoingNegative() {
        let store = makeStore()

        store.log(millilitres: 2500)

        XCTAssertEqual(store.remainingMillilitres, 0)
        XCTAssertEqual(store.fillFraction, 0)
        XCTAssertTrue(store.isGoalMet)
    }

    func testNonPositiveAmountsAreIgnored() {
        let store = makeStore()

        store.log(millilitres: 0)
        store.log(millilitres: -250)

        XCTAssertEqual(store.consumedMillilitres, 0)
        XCTAssertFalse(store.canUndo)
    }

    // MARK: - Undo

    func testUndoRemovesTheMostRecentEntry() {
        let store = makeStore()
        store.log(millilitres: 250)
        clock.date = TestFixtures.date(2026, 8, 28, hour: 11)
        store.log(millilitres: 500)

        XCTAssertTrue(store.canUndo)
        store.undoLastEntry()

        XCTAssertEqual(store.consumedMillilitres, 250, "the 500 ml logged later should be the one removed")
    }

    func testUndoOnEmptyDayIsANoOp() {
        let store = makeStore()

        XCTAssertFalse(store.canUndo)
        store.undoLastEntry()

        XCTAssertEqual(store.consumedMillilitres, 0)
    }

    func testUndoNeverReachesIntoPreviousDays() {
        let yesterday = TestFixtures.date(2026, 8, 27)
        let store = makeStore(seeding: [TestFixtures.day(yesterday, consumed: 1800)])

        XCTAssertFalse(store.canUndo, "today is empty, so there is nothing to undo")
        store.undoLastEntry()

        XCTAssertEqual(store.log(for: yesterday)?.consumedMillilitres, 1800)
    }

    func testResetTodayRefillsTheCarafe() {
        let store = makeStore()
        store.log(millilitres: 750)

        store.resetToday()

        XCTAssertEqual(store.consumedMillilitres, 0)
        XCTAssertEqual(store.fillFraction, 1.0)
    }

    // MARK: - Rollover

    func testRollOverStartsAFreshDayAndArchivesTheOld() {
        let store = makeStore()
        store.log(millilitres: 1200)
        let firstDay = store.startOfToday

        clock.advance(days: 1, calendar: calendar)
        let didRoll = store.rollOverIfNeeded()

        XCTAssertTrue(didRoll)
        XCTAssertEqual(store.consumedMillilitres, 0, "the new day starts empty")
        XCTAssertEqual(store.fillFraction, 1.0, "and the carafe is full again")
        XCTAssertEqual(store.log(for: firstDay)?.consumedMillilitres, 1200, "yesterday is preserved")
    }

    func testRollOverIsIdempotentWithinTheSameDay() {
        let store = makeStore()
        let before = store.days.count

        XCTAssertFalse(store.rollOverIfNeeded())
        XCTAssertFalse(store.rollOverIfNeeded())

        XCTAssertEqual(store.days.count, before)
    }

    func testRollOverAcrossMultipleMissedDaysDoesNotFabricateThem() {
        let store = makeStore()
        store.log(millilitres: 500)

        clock.advance(days: 5, calendar: calendar)
        store.rollOverIfNeeded()

        // Only the day that was actually used and the new today exist.
        XCTAssertEqual(store.days.count, 2)
    }

    // MARK: - Goal changes

    func testChangingGoalAppliesToTodayButNotToHistory() {
        let yesterday = TestFixtures.date(2026, 8, 27)
        let store = makeStore(seeding: [TestFixtures.day(yesterday, goal: 2000, consumed: 2000)])

        store.goalMillilitres = 3000

        XCTAssertEqual(store.today.goalMillilitres, 3000)
        XCTAssertEqual(store.log(for: yesterday)?.goalMillilitres, 2000, "history keeps the goal it was logged under")
        XCTAssertEqual(store.log(for: yesterday)?.isGoalMet, true, "so yesterday still counts as met")
    }

    // MARK: - Settings persistence

    func testSettingsSurviveARestart() {
        let store = makeStore()
        store.goalMillilitres = 2500
        store.glassMillilitres = 330
        store.unitSystem = .us
        store.reminderIntervalMinutes = 45
        store.activeStartHour = 7
        store.activeEndHour = 22
        store.remindersEnabled = false

        let reopened = makeStore()

        XCTAssertEqual(reopened.goalMillilitres, 2500)
        XCTAssertEqual(reopened.glassMillilitres, 330)
        XCTAssertEqual(reopened.unitSystem, .us)
        XCTAssertEqual(reopened.reminderIntervalMinutes, 45)
        XCTAssertEqual(reopened.activeStartHour, 7)
        XCTAssertEqual(reopened.activeEndHour, 22)
        XCTAssertFalse(reopened.remindersEnabled)
    }

    // MARK: - History window

    func testRecentDaysReturnsAFixedWindowEndingToday() {
        let store = makeStore(seeding: [
            TestFixtures.day(TestFixtures.date(2026, 8, 26), consumed: 2000),
            TestFixtures.day(TestFixtures.date(2026, 8, 27), consumed: 1000),
        ])

        let week = store.recentDays(7)

        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.last?.date, store.startOfToday, "the window ends today")
        XCTAssertEqual(week.first?.date, TestFixtures.date(2026, 8, 22), "and spans seven days back")
    }

    func testRecentDaysSynthesisesGapsAsEmptyDays() {
        let store = makeStore(seeding: [TestFixtures.day(TestFixtures.date(2026, 8, 27), consumed: 1000)])

        let week = store.recentDays(7)

        // 24th was never recorded; it should appear as a zero-progress day, not vanish.
        let gap = week.first { $0.date == TestFixtures.date(2026, 8, 24) }
        XCTAssertNotNil(gap)
        XCTAssertEqual(gap?.consumedMillilitres, 0)
        XCTAssertEqual(gap?.progressFraction, 0)
    }

    // MARK: - Persistence round trip

    func testLoggedDrinksSurviveARestart() async {
        let store = makeStore()
        store.log(millilitres: 750)
        store.flushPendingSave()

        let reopened = makeStore()

        XCTAssertEqual(reopened.consumedMillilitres, 750)
        XCTAssertEqual(reopened.remainingMillilitres, 1250)
    }
}
