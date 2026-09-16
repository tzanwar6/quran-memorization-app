import Foundation
import CoreData

class ReviewEngine {
    static func calculateNextDueDate(
        frequency: Frequency,
        from date: Date = Date(),
        intervals: Int = 1,
        calendar: Calendar = .current
    ) -> Date {
        var components = DateComponents()

        if let days = frequency.daysToAdd {
            components.day = days * intervals
        } else if let months = frequency.monthsToAdd {
            components.month = months * intervals
        }

        return calendar.date(byAdding: components, to: date) ?? date
    }

    /// Next due date after completing a review.
    ///
    /// On time or early, the next review is one interval after the current due date. When overdue,
    /// `keepRhythm` steps forward in whole intervals from the original due date until it lands after
    /// today (so a weekly review keeps its weekday), while `restartFromCompletion` counts one interval
    /// from today. Either way an overdue review never leaves the schedule still overdue.
    ///
    /// If `preferences.adjustForRating` is on, a poor rating brings the review back after half the
    /// usual interval and a very poor rating makes it due tomorrow, when that is sooner.
    static func nextDueDateAfterCompletion(
        frequency: Frequency,
        currentDueDate: Date,
        rating: PerformanceRating? = nil,
        preferences: SchedulingPreferences = .default,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: currentDueDate)
        
        var nextDate: Date
        if dueDay < today && preferences.overduePolicy == .restartFromCompletion {
            nextDate = calculateNextDueDate(frequency: frequency, from: today, calendar: calendar)
        } else {
            var intervals = 1
            nextDate = calculateNextDueDate(frequency: frequency, from: dueDay, intervals: intervals, calendar: calendar)
            
            // Adding from the original due date (rather than repeatedly from the previous
            // result) avoids month-end drift, e.g. Jan 31 -> Feb 28 -> Mar 28.
            while nextDate <= today && intervals < 10_000 {
                intervals += 1
                nextDate = calculateNextDueDate(frequency: frequency, from: dueDay, intervals: intervals, calendar: calendar)
            }
        }
        
        if preferences.adjustForRating, let rating = rating, rating.needsEarlierReview {
            let earlyDate = earlyReviewDate(frequency: frequency, rating: rating, today: today, calendar: calendar)
            nextDate = min(nextDate, earlyDate)
        }
        
        return nextDate
    }
    
    private static func earlyReviewDate(
        frequency: Frequency,
        rating: PerformanceRating,
        today: Date,
        calendar: Calendar
    ) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        guard rating == .poor else { return tomorrow }
        
        let fullInterval = calculateNextDueDate(frequency: frequency, from: today, calendar: calendar)
        let intervalDays = calendar.dateComponents([.day], from: today, to: fullInterval).day ?? 1
        return calendar.date(byAdding: .day, value: max(1, intervalDays / 2), to: today) ?? tomorrow
    }
    
    /// Due date after the user changes a schedule's frequency. The new interval is measured
    /// from the last completed review; a schedule that has never been reviewed keeps its
    /// current due date. Never returns a date before today.
    static func dueDateAfterFrequencyChange(
        frequency: Frequency,
        currentDueDate: Date,
        lastCompletedAt: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let today = calendar.startOfDay(for: now)

        guard let lastCompletedAt = lastCompletedAt else {
            return calendar.startOfDay(for: currentDueDate)
        }

        let lastDay = calendar.startOfDay(for: lastCompletedAt)
        let nextDate = calculateNextDueDate(frequency: frequency, from: lastDay, calendar: calendar)
        return max(nextDate, today)
    }

    /// Consecutive days with at least one session, ending today or yesterday.
    /// A streak stays alive through the current day until it passes without a session.
    static func calculateCurrentStreak(
        sessionDates: [Date],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let days = Set(sessionDates.map { calendar.startOfDay(for: $0) })
        guard !days.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        var day: Date
        if days.contains(today) {
            day = today
        } else if days.contains(yesterday) {
            day = yesterday
        } else {
            return 0
        }

        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }

        return streak
    }

    static func calculateLongestStreak(
        sessionDates: [Date],
        calendar: Calendar = .current
    ) -> Int {
        let days = Set(sessionDates.map { calendar.startOfDay(for: $0) }).sorted()
        guard !days.isEmpty else { return 0 }

        var maxStreak = 1
        var currentStreak = 1

        for (previous, day) in zip(days, days.dropFirst()) {
            let daysDiff = calendar.dateComponents([.day], from: previous, to: day).day ?? 0

            if daysDiff == 1 {
                currentStreak += 1
                maxStreak = max(maxStreak, currentStreak)
            } else {
                currentStreak = 1
            }
        }

        return maxStreak
    }
}
