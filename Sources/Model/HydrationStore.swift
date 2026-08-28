import Foundation
import Observation

/// The app's single source of truth: settings, today's log, and history.
///
/// Main-actor isolated because every consumer is a SwiftUI view. Disk writes are
/// debounced and dispatched off the main actor by `scheduleSave()`.
///
/// `historyStore`, `calendar` and `now` are injected so tests can drive rollover
/// and streak logic against a fixed clock without touching the real filesystem.
@MainActor
@Observable
final class HydrationStore {
    // MARK: - Dependencies

    private let historyStore: HistoryStore
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    // MARK: - Settings

    var goalMillilitres: Double {
        didSet {
            guard goalMillilitres != oldValue else { return }
            defaults.set(goalMillilitres, forKey: Keys.goal)
            // Applying the new goal to today keeps the gauge honest the moment you
            // change it. Past days deliberately keep the goal they were logged under.
            if let index = todayIndex {
                days[index].goalMillilitres = goalMillilitres
                scheduleSave()
            }
        }
    }

    var glassMillilitres: Double {
        didSet {
            guard glassMillilitres != oldValue else { return }
            defaults.set(glassMillilitres, forKey: Keys.glass)
        }
    }

    var unitSystem: UnitSystem {
        didSet {
            guard unitSystem != oldValue else { return }
            defaults.set(unitSystem.rawValue, forKey: Keys.unitSystem)
        }
    }

    var remindersEnabled: Bool {
        didSet {
            guard remindersEnabled != oldValue else { return }
            defaults.set(remindersEnabled, forKey: Keys.remindersEnabled)
        }
    }

    var reminderIntervalMinutes: Int {
        didSet {
            guard reminderIntervalMinutes != oldValue else { return }
            defaults.set(reminderIntervalMinutes, forKey: Keys.reminderInterval)
        }
    }

    var activeStartHour: Int {
        didSet {
            guard activeStartHour != oldValue else { return }
            defaults.set(activeStartHour, forKey: Keys.activeStartHour)
        }
    }

    var activeEndHour: Int {
        didSet {
            guard activeEndHour != oldValue else { return }
            defaults.set(activeEndHour, forKey: Keys.activeEndHour)
        }
    }

    // MARK: - Data

    /// All known days, ascending by date, including today once `rollOverIfNeeded` has run.
    private(set) var days: [DayLog] = []

    private var saveTask: Task<Void, Never>?

    // MARK: - Init

    init(
        historyStore: HistoryStore = HistoryStore(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.historyStore = historyStore
        self.defaults = defaults
        self.calendar = calendar
        self.now = now

        defaults.register(defaults: [
            Keys.goal: Defaults.goal,
            Keys.glass: Defaults.glass,
            Keys.unitSystem: UnitSystem.metric.rawValue,
            Keys.remindersEnabled: true,
            Keys.reminderInterval: Defaults.reminderIntervalMinutes,
            Keys.activeStartHour: Defaults.activeStartHour,
            Keys.activeEndHour: Defaults.activeEndHour,
        ])

        goalMillilitres = defaults.double(forKey: Keys.goal)
        glassMillilitres = defaults.double(forKey: Keys.glass)
        unitSystem = UnitSystem(rawValue: defaults.string(forKey: Keys.unitSystem) ?? "") ?? .metric
        remindersEnabled = defaults.bool(forKey: Keys.remindersEnabled)
        reminderIntervalMinutes = defaults.integer(forKey: Keys.reminderInterval)
        activeStartHour = defaults.integer(forKey: Keys.activeStartHour)
        activeEndHour = defaults.integer(forKey: Keys.activeEndHour)

        days = historyStore.load()
        rollOverIfNeeded()
    }

    // MARK: - Today

    var startOfToday: Date {
        calendar.startOfDay(for: now())
    }

    private var todayIndex: Int? {
        let today = startOfToday
        return days.firstIndex { calendar.isDate($0.date, inSameDayAs: today) }
    }

    /// Today's log. Always present after `rollOverIfNeeded()`; the fallback exists
    /// only so this stays non-optional for views.
    var today: DayLog {
        if let index = todayIndex { return days[index] }
        return DayLog(date: startOfToday, goalMillilitres: goalMillilitres)
    }

    var remainingMillilitres: Double { today.remainingMillilitres }
    var consumedMillilitres: Double { today.consumedMillilitres }
    var fillFraction: Double { today.fillFraction }
    var isGoalMet: Bool { today.isGoalMet }

    /// Creates today's log if the calendar day has advanced since the last one.
    ///
    /// Called on popover open, on a midnight timer, and on wake — a timer alone is
    /// unreliable across sleep, so the three together cover the realistic cases.
    /// Returns `true` when a new day was started.
    @discardableResult
    func rollOverIfNeeded() -> Bool {
        guard todayIndex == nil else { return false }
        days.append(DayLog(date: startOfToday, goalMillilitres: goalMillilitres))
        days.sort { $0.date < $1.date }
        scheduleSave()
        return true
    }

    // MARK: - Logging

    /// Records a drink of `millilitres` at the current time. Non-positive amounts are ignored.
    func log(millilitres: Double) {
        guard millilitres > 0 else { return }
        rollOverIfNeeded()
        guard let index = todayIndex else { return }
        days[index].entries.append(DrinkEntry(timestamp: now(), millilitres: millilitres))
        scheduleSave()
    }

    /// Logs one glass at the configured glass size.
    func logGlass() {
        log(millilitres: glassMillilitres)
    }

    /// Whether there is anything to undo today.
    var canUndo: Bool {
        !(todayIndex.map { days[$0].entries.isEmpty } ?? true)
    }

    /// Removes the most recent entry logged today. Never reaches into previous days.
    func undoLastEntry() {
        guard let index = todayIndex, !days[index].entries.isEmpty else { return }
        let lastByTime = days[index].entries.indices.max { days[index].entries[$0].timestamp < days[index].entries[$1].timestamp }
        if let lastByTime {
            days[index].entries.remove(at: lastByTime)
            scheduleSave()
        }
    }

    /// Clears every entry logged today, refilling the carafe.
    func resetToday() {
        guard let index = todayIndex, !days[index].entries.isEmpty else { return }
        days[index].entries.removeAll()
        scheduleSave()
    }

    // MARK: - Editing past days

    /// Whether a day can be edited. Any day up to and including today qualifies;
    /// the future does not, since there is nothing to correct yet.
    func canEdit(_ date: Date) -> Bool {
        calendar.startOfDay(for: date) <= startOfToday
    }

    /// Overwrites the total consumed on `date`, creating the day if it was never recorded.
    ///
    /// The day's individual entries are replaced by a **single** entry carrying the
    /// new total. Carafe has no intraday view, so the separate timestamps carry no
    /// information the user can see, and collapsing them keeps "the total is what I
    /// set" true rather than leaving the sum to drift from the displayed figure.
    /// Today's granular history is still built up normally by the quick-add buttons;
    /// only an explicit edit collapses it.
    ///
    /// Negative amounts clamp to zero. Future dates are ignored.
    func setConsumed(_ millilitres: Double, for date: Date) {
        guard let index = ensureDay(date) else { return }
        let amount = max(0, millilitres)

        if amount == 0 {
            days[index].entries.removeAll()
        } else {
            days[index].entries = [
                DrinkEntry(timestamp: editTimestamp(for: days[index].date), millilitres: amount)
            ]
        }
        scheduleSave()
    }

    /// Moves a day's total by `delta`, clamping at zero.
    func adjustConsumed(by delta: Double, for date: Date) {
        let current = log(for: date)?.consumedMillilitres ?? 0
        setConsumed(current + delta, for: date)
    }

    /// The index of `date`'s log, inserting an empty one if the day was never recorded.
    ///
    /// Returns `nil` for future dates.
    private func ensureDay(_ date: Date) -> Int? {
        let start = calendar.startOfDay(for: date)
        guard start <= startOfToday else { return nil }

        if let existing = days.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: start) }) {
            return existing
        }
        // A day being filled in for the first time adopts the current goal — there is
        // no earlier goal on record to preserve. Days that already exist keep theirs.
        days.append(DayLog(date: start, goalMillilitres: goalMillilitres))
        days.sort { $0.date < $1.date }
        return days.firstIndex { calendar.isDate($0.date, inSameDayAs: start) }
    }

    /// When to stamp an edited total: the actual time for today, midday for any
    /// past day, so the entry always falls inside the day it belongs to.
    private func editTimestamp(for startOfDay: Date) -> Date {
        if calendar.isDate(startOfDay, inSameDayAs: startOfToday) { return now() }
        return calendar.date(byAdding: .hour, value: 12, to: startOfDay) ?? startOfDay
    }

    // MARK: - History

    func log(for date: Date) -> DayLog? {
        days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    /// The last `count` days ending today, oldest first.
    ///
    /// Days with no record are synthesised as empty logs so the history strip keeps a
    /// constant width and gaps read as "drank nothing" rather than silently collapsing.
    func recentDays(_ count: Int) -> [DayLog] {
        let today = startOfToday
        return (0..<count).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return log(for: date) ?? DayLog(date: date, goalMillilitres: goalMillilitres)
        }
    }

    /// Consecutive days meeting the goal, counting backwards from today.
    ///
    /// A day in progress does not break the streak: if today's goal is not met yet,
    /// the count resumes from yesterday. Only a fully elapsed missed day breaks it.
    var currentStreak: Int {
        var streak = 0
        var cursor = startOfToday

        if log(for: cursor)?.isGoalMet == true {
            streak += 1
        }

        guard var previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { return streak }
        cursor = previous

        while log(for: cursor)?.isGoalMet == true {
            streak += 1
            guard let earlier = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            previous = earlier
            cursor = previous
        }

        return streak
    }

    // MARK: - Backup and restore

    /// The location of the JSON history file, for showing the user where their data lives.
    var historyFileURL: URL { historyStore.fileURL }

    /// A complete snapshot: history plus settings.
    func makeBackupArchive(exportedAt: Date? = nil) -> BackupArchive {
        BackupArchive(
            format: BackupArchive.formatIdentifier,
            version: BackupArchive.currentVersion,
            exportedAt: exportedAt ?? now(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            settings: BackupArchive.Settings(
                goalMillilitres: goalMillilitres,
                glassMillilitres: glassMillilitres,
                unitSystem: unitSystem,
                remindersEnabled: remindersEnabled,
                reminderIntervalMinutes: reminderIntervalMinutes,
                activeStartHour: activeStartHour,
                activeEndHour: activeEndHour
            ),
            days: days
        )
    }

    /// Replaces all history and settings with the contents of an archive.
    ///
    /// A restore **replaces** rather than merges. Merging would need a rule for two
    /// records of the same day disagreeing, and any rule silently discards data the
    /// user may have wanted; replacing is at least predictable, and the UI warns
    /// before doing it.
    ///
    /// Absent settings are left as they are, so an archive that omits a field does
    /// not reset it to a default.
    func restore(from archive: BackupArchive) {
        if let value = archive.settings.goalMillilitres { goalMillilitres = value }
        if let value = archive.settings.glassMillilitres { glassMillilitres = value }
        if let value = archive.settings.unitSystem { unitSystem = value }
        if let value = archive.settings.remindersEnabled { remindersEnabled = value }
        if let value = archive.settings.reminderIntervalMinutes { reminderIntervalMinutes = value }
        if let value = archive.settings.activeStartHour { activeStartHour = value }
        if let value = archive.settings.activeEndHour { activeEndHour = value }

        days = archive.days.sorted { $0.date < $1.date }
        // The archive may predate today, so make sure today exists again.
        rollOverIfNeeded()
        flushPendingSave()
    }

    // MARK: - Persistence

    /// Debounces disk writes: rapid logging (or an undo immediately after a log)
    /// collapses into a single write, off the main actor.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = days
        let store = historyStore
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) { store.save(snapshot) }.value
            self?.saveTask = nil
        }
    }

    /// Writes immediately, bypassing the debounce. Call on app termination so a
    /// quit within the debounce window cannot lose the last drink.
    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        historyStore.save(days)
    }

    // MARK: - Constants

    private enum Keys {
        static let goal = "goalMillilitres"
        static let glass = "glassMillilitres"
        static let unitSystem = "unitSystem"
        static let remindersEnabled = "remindersEnabled"
        static let reminderInterval = "reminderIntervalMinutes"
        static let activeStartHour = "activeStartHour"
        static let activeEndHour = "activeEndHour"
    }

    enum Defaults {
        static let goal: Double = 2000
        static let glass: Double = 250
        static let reminderIntervalMinutes = 60
        static let activeStartHour = 8
        static let activeEndHour = 20
    }
}
