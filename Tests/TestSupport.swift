import Foundation

@testable import Carafe

/// A clock the tests can move. `HydrationStore` takes `now` as a `@Sendable` closure,
/// so the backing storage needs its own lock to satisfy Swift 6 concurrency checking.
final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _date: Date

    init(_ date: Date) {
        _date = date
    }

    var date: Date {
        get { lock.withLock { _date } }
        set { lock.withLock { _date = newValue } }
    }

    /// A closure suitable for `HydrationStore(now:)`.
    var provider: @Sendable () -> Date {
        { [self] in date }
    }

    func advance(days: Int, calendar: Calendar) {
        date = calendar.date(byAdding: .day, value: days, to: date)!
    }
}

enum TestFixtures {
    /// A fixed calendar in UTC, so day boundaries never depend on where the tests run.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Midnight UTC on the given date.
    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    /// A day log with a single entry totalling `consumed`.
    static func day(_ date: Date, goal: Double = 2000, consumed: Double) -> DayLog {
        DayLog(
            date: date,
            goalMillilitres: goal,
            entries: consumed > 0 ? [DrinkEntry(timestamp: date, millilitres: consumed)] : []
        )
    }

    /// A scratch file URL in a unique temporary directory.
    static func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("carafe-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    /// A UserDefaults suite isolated from the real app and from other tests.
    static func isolatedDefaults() -> UserDefaults {
        let name = "com.tristandealwis.carafe.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
