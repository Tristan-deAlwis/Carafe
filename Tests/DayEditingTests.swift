import XCTest

@testable import Carafe

/// Editing the amount drunk on a past day.
@MainActor
final class DayEditingTests: XCTestCase {
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

    // MARK: - Setting a total

    func testEditingAPastDayOverwritesItsTotal() {
        let store = makeStore(seeding: [TestFixtures.day(daysAgo(2), consumed: 800)])

        store.setConsumed(1750, for: daysAgo(2))

        XCTAssertEqual(store.log(for: daysAgo(2))?.consumedMillilitres, 1750)
    }

    func testEditingCollapsesTheDayToASingleEntry() {
        let store = makeStore()
        store.log(millilitres: 250)
        store.log(millilitres: 250)

        store.setConsumed(1000, for: today)

        // The displayed total must equal what was set, so the separate entries are
        // replaced rather than added to.
        XCTAssertEqual(store.today.entries.count, 1)
        XCTAssertEqual(store.consumedMillilitres, 1000)
    }

    func testEditingADayThatWasNeverRecordedCreatesIt() {
        let store = makeStore()
        XCTAssertNil(store.log(for: daysAgo(3)))

        store.setConsumed(1200, for: daysAgo(3))

        XCTAssertEqual(store.log(for: daysAgo(3))?.consumedMillilitres, 1200)
    }

    func testANewlyCreatedDayAdoptsTheCurrentGoal() {
        let store = makeStore()
        store.goalMillilitres = 2500

        store.setConsumed(1000, for: daysAgo(3))

        XCTAssertEqual(store.log(for: daysAgo(3))?.goalMillilitres, 2500)
    }

    func testEditingAnExistingDayKeepsItsOwnGoal() {
        let store = makeStore(seeding: [TestFixtures.day(daysAgo(2), goal: 1500, consumed: 500)])

        store.goalMillilitres = 3000
        store.setConsumed(1600, for: daysAgo(2))

        XCTAssertEqual(store.log(for: daysAgo(2))?.goalMillilitres, 1500, "history keeps the goal it was logged under")
        XCTAssertEqual(store.log(for: daysAgo(2))?.isGoalMet, true)
    }

    func testSettingZeroClearsTheDay() {
        let store = makeStore(seeding: [TestFixtures.day(daysAgo(1), consumed: 1500)])

        store.setConsumed(0, for: daysAgo(1))

        XCTAssertEqual(store.log(for: daysAgo(1))?.consumedMillilitres, 0)
        XCTAssertEqual(store.log(for: daysAgo(1))?.entries.count, 0)
    }

    func testNegativeAmountsClampToZero() {
        let store = makeStore(seeding: [TestFixtures.day(daysAgo(1), consumed: 500)])

        store.setConsumed(-250, for: daysAgo(1))

        XCTAssertEqual(store.log(for: daysAgo(1))?.consumedMillilitres, 0)
    }

    func testEditedEntryIsTimestampedInsideTheDayItBelongsTo() {
        let store = makeStore()

        store.setConsumed(1000, for: daysAgo(4))

        let entry = try? XCTUnwrap(store.log(for: daysAgo(4))?.entries.first)
        XCTAssertNotNil(entry)
        XCTAssertTrue(
            calendar.isDate(entry!.timestamp, inSameDayAs: daysAgo(4)),
            "an edit stamped outside its own day would sort into the wrong bar"
        )
    }

    // MARK: - Adjusting

    func testAdjustingMovesTheTotalByADelta() {
        let store = makeStore(seeding: [TestFixtures.day(daysAgo(1), consumed: 1000)])

        store.adjustConsumed(by: 250, for: daysAgo(1))

        XCTAssertEqual(store.log(for: daysAgo(1))?.consumedMillilitres, 1250)
    }

    func testAdjustingBelowZeroClamps() {
        let store = makeStore(seeding: [TestFixtures.day(daysAgo(1), consumed: 200)])

        store.adjustConsumed(by: -500, for: daysAgo(1))

        XCTAssertEqual(store.log(for: daysAgo(1))?.consumedMillilitres, 0)
    }

    func testAdjustingADayWithNoRecordStartsFromZero() {
        let store = makeStore()

        store.adjustConsumed(by: 250, for: daysAgo(5))

        XCTAssertEqual(store.log(for: daysAgo(5))?.consumedMillilitres, 250)
    }

    // MARK: - Boundaries

    func testFutureDaysCannotBeEdited() {
        let store = makeStore()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        XCTAssertFalse(store.canEdit(tomorrow))
        store.setConsumed(1000, for: tomorrow)

        XCTAssertNil(store.log(for: tomorrow), "editing the future must not fabricate a day")
    }

    func testTodayAndPastDaysCanBeEdited() {
        let store = makeStore()

        XCTAssertTrue(store.canEdit(today))
        XCTAssertTrue(store.canEdit(daysAgo(1)))
        XCTAssertTrue(store.canEdit(daysAgo(100)))
    }

    func testEditingTodayUpdatesTheGaugeImmediately() {
        let store = makeStore()

        store.setConsumed(1500, for: today)

        XCTAssertEqual(store.remainingMillilitres, 500)
        XCTAssertEqual(store.fillFraction, 0.25)
    }

    func testAnyTimeOfDayResolvesToTheSameDay() {
        let store = makeStore()

        store.setConsumed(600, for: TestFixtures.date(2026, 8, 26, hour: 23))
        store.adjustConsumed(by: 400, for: TestFixtures.date(2026, 8, 26, hour: 2))

        XCTAssertEqual(store.log(for: daysAgo(2))?.consumedMillilitres, 1000)
    }

    // MARK: - Knock-on effects

    func testEditingAPastDayCanRepairAStreak() {
        let store = makeStore(seeding: [
            TestFixtures.day(daysAgo(3), consumed: 2000),
            TestFixtures.day(daysAgo(2), consumed: 2000),
            TestFixtures.day(daysAgo(1), consumed: 900),
        ])
        XCTAssertEqual(store.currentStreak, 0, "yesterday's shortfall breaks it")

        store.setConsumed(2000, for: daysAgo(1))

        XCTAssertEqual(store.currentStreak, 3, "correcting yesterday restores the run")
    }

    func testEditingAPastDayCanBreakAStreak() {
        let store = makeStore(seeding: [
            TestFixtures.day(daysAgo(2), consumed: 2000),
            TestFixtures.day(daysAgo(1), consumed: 2000),
        ])
        XCTAssertEqual(store.currentStreak, 2)

        store.setConsumed(100, for: daysAgo(1))

        XCTAssertEqual(store.currentStreak, 0)
    }

    func testEditsAppearInTheHistoryWindow() {
        let store = makeStore()

        store.setConsumed(1000, for: daysAgo(4))

        let edited = store.recentDays(7).first { calendar.isDate($0.date, inSameDayAs: daysAgo(4)) }
        XCTAssertEqual(edited?.consumedMillilitres, 1000)
        XCTAssertEqual(edited?.progressFraction, 0.5)
    }

    func testEditsSurviveARestart() {
        let store = makeStore()
        store.setConsumed(1750, for: daysAgo(3))
        store.flushPendingSave()

        let reopened = makeStore()

        XCTAssertEqual(reopened.log(for: daysAgo(3))?.consumedMillilitres, 1750)
    }

    func testUndoStillOnlyAffectsToday() {
        let store = makeStore()
        store.setConsumed(1500, for: daysAgo(1))
        store.log(millilitres: 250)

        store.undoLastEntry()

        XCTAssertEqual(store.consumedMillilitres, 0)
        XCTAssertEqual(store.log(for: daysAgo(1))?.consumedMillilitres, 1500, "the past day is untouched")
    }
}
