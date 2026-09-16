import Foundation

struct PlannedReminder: Equatable {
    let fireDate: Date
    let title: String
    let body: String
    let badge: Int
}

enum ReminderPlanner {
    /// iOS keeps at most 64 pending notifications per app; a month leaves plenty of headroom.
    static let defaultDays = 30

    /// One reminder per upcoming day that has reviews due, describing what's due.
    ///
    /// Assumes nothing is completed after `now`: a review due today still counts (as overdue)
    /// on later days. Plans are rebuilt whenever reviews are completed or schedules change,
    /// so each reminder reflects the latest state.
    static func plan(
        schedules: [ScheduleWithSurah],
        hour: Int,
        minute: Int,
        days: Int = defaultDays,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [PlannedReminder] {
        let today = calendar.startOfDay(for: now)
        let active = schedules
            .filter { $0.isActive }
            .sorted { $0.nextDueDate < $1.nextDueDate }

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fireDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  fireDate > now else {
                return nil
            }

            let due = active.filter { calendar.startOfDay(for: $0.nextDueDate) <= day }
            guard !due.isEmpty else { return nil }

            let overdueCount = due.filter { calendar.startOfDay(for: $0.nextDueDate) < day }.count

            return PlannedReminder(
                fireDate: fireDate,
                title: "🕌 Time to review",
                body: body(names: due.map(\.surahEnglishName), overdueCount: overdueCount),
                badge: due.count
            )
        }
    }

    static func body(names: [String], overdueCount: Int) -> String {
        let summary: String
        switch names.count {
        case 1:
            return overdueCount > 0 ? "\(names[0]) is overdue for review." : "\(names[0]) is due for review."
        case 2:
            summary = "2 reviews due: \(names[0]) and \(names[1])."
        default:
            summary = "\(names.count) reviews due: \(names[0]), \(names[1]) and \(names.count - 2) more."
        }

        return overdueCount > 0 ? "\(summary) \(overdueCount) overdue." : summary
    }
}
