import XCTest

@testable import Carafe

/// The streak rule under test:
///
///   A day counts when consumed >= goal. The streak counts consecutive qualifying
///   days backwards from today — but a day still in progress must not break it, so
///   when today has not qualified yet the count resumes from yesterday.
@MainActor
final class StreakTests: XCTestCase {
    private var clock: MutableClock!
    private var fileURL: URL!
    private var calendar: Calendar!

    /// Today, for every test in this class.
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

    private func makeStore(seeding days: [DayLog]) -> HydrationStore {
        HistoryStore(fileURL: fileURL).save(days)
        return HydrationStore(
            historyStore: HistoryStore(fileURL: fileURL),
            defaults: TestFixtures.isolatedDefaults(),
            calendar: calendar,
            now: clock.provider
        )
    }

    func testNoHistoryMeansNoStreak() {
        let store = makeStore(seeding: [])

        XCTAssertEqual(store.currentStreak, 0)
    }

    func testTodayStillInProgressDoesNotBreakTheStreak() {
        let store = makeStore(seeding: [
            TestFixtures.day(daysAgo(2), consumed: 2000),
            TestFixtures.day(daysAgo(1), consumed: 2000),
        ])

        // Today is untouched — the whole point of the rule.
        XCTAssertFalse(store.isGoalMet)
        XCTAssertEqual(store.currentStreak, 2)
    }

    func testMeetingTodaysGoalExtendsTheStreak() {
        let store = makeStore(seeding: [
            TestFixtures.day(daysAgo(2), consumed: 2000),
            TestFixtures.day(daysAgo(1), consumed: 2000),
        ])

        store.log(millilitres: 2000)

        XCTAssertTrue(store.isGoalMet)
        XCTAssertEqual(store.currentStreak, 3)
    }

    func testAnElapsedMissedDayBreaksTheStreak() {
        let store = makeStore(seeding: [
            TestFixtures.day(daysAgo(3), consumed: 2000),
            TestFixtures.day(daysAgo(2), consumed: 2000),
            TestFixtures.day(daysAgo(1), consumed: 900),
        ])

        XCTAssertEqual(store.currentStreak, 0, "yesterday fell short, so nothing earlier counts")
    }

    func testTodayAloneCountsWhenYesterdayWasMissed() {
        let store = makeStore(seeding: [
            TestFixtures.day(daysAgo(2), consumed: 2000),
            TestFixtures.day(daysAgo(1), consumed: 500),
        ])

        store.log(millilitres: 2000)

        XCTAssertEqual(store.currentStreak, 1)
    }

    func testAMissingDayBreaksTheStreakJustLikeAShortfall() {
        // No record at all for two days ago — the app was not running, or nothing was logged.
        let store = makeStore(seeding: [
            TestFixtures.day(daysAgo(3), consumed: 2000),
            TestFixtures.day(daysAgo(1), consumed: 2000),
        ])

        XCTAssertEqual(store.currentStreak, 1, "only yesterday counts; the gap stops the walk")
    }

    func testExactlyMeetingTheGoalCounts() {
        let store = makeStore(seeding: [TestFixtures.day(daysAgo(1), goal: 2000, consumed: 2000)])

        XCTAssertEqual(store.currentStreak, 1, "consumed == goal must qualify")
    }

    func testStreakRespectsThePerDayGoalNotTheCurrentOne() {
        // Logged under a 1500 ml goal and met it. Raising the goal today must not
        // retroactively invalidate that day.
        let store = makeStore(seeding: [TestFixtures.day(daysAgo(1), goal: 1500, consumed: 1600)])

        store.goalMillilitres = 3000

        XCTAssertEqual(store.currentStreak, 1)
    }

    func testLongStreakCountsEveryConsecutiveDay() {
        let seeded = (1...10).map { TestFixtures.day(daysAgo($0), consumed: 2000) }
        let store = makeStore(seeding: seeded)

        XCTAssertEqual(store.currentStreak, 10)
    }
}
