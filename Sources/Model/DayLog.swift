import Foundation

/// One calendar day's hydration record.
///
/// The goal is stored per-day rather than read from settings, so that changing
/// your daily goal never rewrites history: past days keep the goal that was
/// actually in force when they were logged.
struct DayLog: Codable, Identifiable, Equatable, Sendable {
    /// Midnight of the day this log covers, in the user's local calendar.
    let date: Date
    var goalMillilitres: Double
    var entries: [DrinkEntry]

    var id: Date { date }

    init(date: Date, goalMillilitres: Double, entries: [DrinkEntry] = []) {
        self.date = date
        self.goalMillilitres = goalMillilitres
        self.entries = entries
    }

    var consumedMillilitres: Double {
        entries.reduce(0) { $0 + $1.millilitres }
    }

    /// How much is still left to drink. Never negative — overdrinking clamps to zero
    /// rather than reporting a negative remainder.
    var remainingMillilitres: Double {
        max(0, goalMillilitres - consumedMillilitres)
    }

    var isGoalMet: Bool {
        consumedMillilitres >= goalMillilitres
    }

    /// Fraction of the carafe still holding water, from 1.0 (untouched) to 0.0 (goal met).
    ///
    /// This drives the gauge directly: Carafe *drains* as you drink, so the water
    /// level is the amount remaining rather than the amount consumed.
    var fillFraction: Double {
        guard goalMillilitres > 0 else { return 0 }
        return min(1, max(0, remainingMillilitres / goalMillilitres))
    }

    /// Progress toward the goal, from 0.0 to 1.0. The complement of `fillFraction`,
    /// used for the history strip where "taller bar = drank more" is the natural reading.
    var progressFraction: Double {
        guard goalMillilitres > 0 else { return 0 }
        return min(1, max(0, consumedMillilitres / goalMillilitres))
    }
}
