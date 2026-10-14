import Foundation

// Shared with the Screen Time extensions, so nothing here may depend on app-only code.

enum LockStatus: Equatable {
    case disabled
    /// Nothing is due, either because it's a quiet day or because every review is logged.
    case unlockedForToday
    case locked(remaining: Int)
}

enum LockPolicy {
    /// How long the weekly change window of a permanent lock stays open.
    static let changeWindowLength: TimeInterval = 30 * 60

    static func remainingCount(dueDates: [Date], now: Date = Date(), calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        return dueDates.filter { calendar.startOfDay(for: $0) <= today }.count
    }

    /// The apps are locked from midnight for as long as a review is due.
    static func status(state: SharedLockState, now: Date = Date(), calendar: Calendar = .current) -> LockStatus {
        guard state.isEnabled else { return .disabled }
        let remaining = remainingCount(dueDates: state.dueDates, now: now, calendar: calendar)
        return remaining > 0 ? .locked(remaining: remaining) : .unlockedForToday
    }

    static func shouldShield(state: SharedLockState, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if case .locked = status(state: state, now: now, calendar: calendar) { return true }
        return false
    }

    /// When things will next change without anything being saved: midnight, which can bring new
    /// reviews, or the weekly change window opening or closing.
    static func nextChange(state: SharedLockState, now: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard state.isEnabled else { return nil }
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        let changeWindowEdge = state.commitment.flatMap { commitment in
            openChangeWindow(commitment: commitment, now: now, calendar: calendar)?.end
                ?? nextChangeWindow(commitment: commitment, after: now, calendar: calendar)
        }
        return [midnight, changeWindowEdge].compactMap { $0 }.min()
    }

    // MARK: - Permanent lock

    /// The weekly change window that is open at `now`, if one is.
    static func openChangeWindow(commitment: LockCommitment, now: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        // A window that opens late in the evening is still open just after midnight, so yesterday's counts too.
        for dayOffset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)),
                  calendar.component(.weekday, from: day) == commitment.windowWeekday,
                  let opens = calendar.date(bySettingHour: commitment.windowHour, minute: commitment.windowMinute, second: 0, of: day)
            else { continue }
            let window = DateInterval(start: opens, duration: changeWindowLength)
            if now >= window.start && now < window.end { return window }
        }
        return nil
    }

    /// When the change window next opens after `now`.
    static func nextChangeWindow(commitment: LockCommitment, after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let opening = DateComponents(hour: commitment.windowHour, minute: commitment.windowMinute, weekday: commitment.windowWeekday)
        return calendar.nextDate(after: now, matching: opening, matchingPolicy: .nextTime)
    }

    /// Whether the lock's settings are fixed right now: it has been made permanent, and its
    /// weekly change window isn't open.
    static func isFrozen(state: SharedLockState, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard state.isEnabled, let commitment = state.commitment else { return false }
        return openChangeWindow(commitment: commitment, now: now, calendar: calendar) == nil
    }

    /// While the settings are fixed, a passage that is due can't be paused, deleted or rescheduled:
    /// any of those would unlock the apps without the review being done.
    static func holdsPassage(
        dueDate: Date,
        isActive: Bool,
        state: SharedLockState,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard isActive, isFrozen(state: state, now: now, calendar: calendar) else { return false }
        return calendar.startOfDay(for: dueDate) <= calendar.startOfDay(for: now)
    }
}
