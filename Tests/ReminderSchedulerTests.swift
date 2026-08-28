import XCTest

@testable import Carafe

/// Slot maths only. Actually scheduling notifications needs a real notification
/// centre and user consent, so that path is exercised by hand — see the manual
/// checks in the README.
final class ReminderSchedulerTests: XCTestCase {
    private func slots(_ start: Int, _ end: Int, every interval: Int) -> [ReminderScheduler.Slot] {
        ReminderScheduler.slots(startHour: start, endHour: end, intervalMinutes: interval)
    }

    func testHourlySlotsAcrossTheDefaultWindow() {
        let result = slots(8, 20, every: 60)

        XCTAssertEqual(result.count, 12)
        XCTAssertEqual(result.first, ReminderScheduler.Slot(hour: 8, minute: 0))
        XCTAssertEqual(result.last, ReminderScheduler.Slot(hour: 19, minute: 0))
    }

    func testEndHourIsExclusive() {
        // A window ending at 20:00 must not fire at 20:00.
        XCTAssertFalse(slots(8, 20, every: 60).contains(ReminderScheduler.Slot(hour: 20, minute: 0)))
    }

    func testSubHourIntervalsProduceMinuteOffsets() {
        let result = slots(9, 11, every: 45)

        XCTAssertEqual(result, [
            ReminderScheduler.Slot(hour: 9, minute: 0),
            ReminderScheduler.Slot(hour: 9, minute: 45),
            ReminderScheduler.Slot(hour: 10, minute: 30),
        ])
    }

    func testIntervalWiderThanTheWindowStillFiresOnce() {
        XCTAssertEqual(slots(8, 9, every: 180), [ReminderScheduler.Slot(hour: 8, minute: 0)])
    }

    func testInvertedHoursProduceNoSlots() {
        XCTAssertTrue(slots(20, 8, every: 60).isEmpty)
    }

    func testEqualHoursProduceNoSlots() {
        XCTAssertTrue(slots(9, 9, every: 60).isEmpty)
    }

    func testNonPositiveIntervalTerminatesRatherThanLooping() {
        // Guards an infinite loop, which in a menu bar app would be an invisible hang.
        XCTAssertTrue(slots(8, 20, every: 0).isEmpty)
        XCTAssertTrue(slots(8, 20, every: -30).isEmpty)
    }

    func testSlotCountStaysUnderTheSystemPendingLimit() {
        // macOS keeps at most 64 pending requests; exceeding it silently drops them.
        let result = slots(0, 24, every: 1)

        XCTAssertLessThanOrEqual(result.count, ReminderScheduler.maximumSlots)
        XCTAssertLessThan(result.count, 64)
    }

    func testEveryPresetIntervalStaysUnderTheLimitAcrossAFullDay() {
        for interval in [30, 45, 60, 90, 120, 180] {
            let count = slots(0, 24, every: interval).count
            XCTAssertLessThan(count, 64, "interval \(interval) produced \(count) slots")
        }
    }
}
