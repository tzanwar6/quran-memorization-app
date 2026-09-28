import Foundation

/// Counts passages, not taps: multiple logs for one schedule count once per day.
struct DailyReviewSummary {
    enum State: Equatable {
        case gettingStarted, reviewsDue, finished, quietDay, paused
    }

    let remaining: [ScheduleWithSurah]
    let completedCount: Int
    let nextReviewDate: Date?
    let state: State
    var totalCount: Int { completedCount + remaining.count }

    init(schedules: [ScheduleWithSurah], sessions: [SessionWithSchedule], now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let active = schedules.filter(\.isActive)
        remaining = active.filter { calendar.startOfDay(for: $0.nextDueDate) <= today }
            .sorted {
                if $0.nextDueDate != $1.nextDueDate { return $0.nextDueDate < $1.nextDueDate }
                return $0.id.uuidString < $1.id.uuidString
            }
        let dueIDs = Set(remaining.map(\.id))
        let scheduleIDs = Set(schedules.map(\.id))
        let completedIDs = Set(sessions.filter {
            calendar.isDate($0.completedAt, inSameDayAs: now)
        }.map(\.scheduleId))
        // A passage deliberately made due again still needs attention.
        completedCount = completedIDs.intersection(scheduleIDs).subtracting(dueIDs).count
        nextReviewDate = active.map(\.nextDueDate).filter { calendar.startOfDay(for: $0) > today }.min()

        if schedules.isEmpty { state = .gettingStarted }
        else if !remaining.isEmpty { state = .reviewsDue }
        else if completedCount > 0 { state = .finished }
        else if active.isEmpty { state = .paused }
        else { state = .quietDay }
    }
}
