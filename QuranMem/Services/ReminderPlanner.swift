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
        hifz: HifzForecast? = nil,
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
            let lesson = hifz?.lessonDue(on: day) ?? false
            let recent = hifz?.recentReviewDue(on: day) ?? false
            guard !due.isEmpty || lesson || recent else { return nil }

            let overdueCount = due.filter { calendar.startOfDay(for: $0.nextDueDate) < day }.count
            let revisionBody = due.isEmpty ? nil : body(names: due.map(\.surahEnglishName), overdueCount: overdueCount)

            return PlannedReminder(
                fireDate: fireDate,
                title: due.isEmpty ? "🕌 Time to memorize" : "🕌 Time to review",
                body: body(lesson: lesson, recentReview: recent, revision: revisionBody),
                badge: due.count + (lesson ? 1 : 0) + (recent ? 1 : 0)
            )
        }
    }

    /// Puts the plan's work first: "New lesson and recent review. Al-Mulk is due for review."
    static func body(lesson: Bool, recentReview: Bool, revision: String?) -> String {
        let work: String?
        switch (lesson, recentReview) {
        case (true, true): work = "new lesson and recent review"
        case (true, false): work = "new lesson"
        case (false, true): work = "recent review"
        case (false, false): work = nil
        }
        guard let work else { return revision ?? "" }
        guard let revision else {
            return "Your \(work) \(lesson && recentReview ? "are" : "is") waiting."
        }
        return "\(work.prefix(1).uppercased() + work.dropFirst()). \(revision)"
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
