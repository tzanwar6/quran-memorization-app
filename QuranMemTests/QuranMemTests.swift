//
//  QuranMemTests.swift
//  QuranMemTests
//
//  Created by Taha Anwar on 11/9/25.
//

import CoreData
import Foundation
import Testing
@testable import QuranMem

// Fixed calendar and dates so results don't depend on the machine's time zone or clock.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    date(year, month, day, hour: 0)
}

// MARK: - Due date after completing a review

struct NextDueDateAfterCompletionTests {
    private let now = date(2026, 3, 10, hour: 18)

    private func next(_ frequency: Frequency, due: Date) -> Date {
        ReviewEngine.nextDueDateAfterCompletion(frequency: frequency, currentDueDate: due, now: now, calendar: calendar)
    }

    @Test func dailyDueTodayMovesToTomorrow() {
        #expect(next(.daily, due: date(2026, 3, 10)) == day(2026, 3, 11))
    }

    @Test func overdueDailyMovesToTomorrowNotStillOverdue() {
        #expect(next(.daily, due: date(2026, 3, 5)) == day(2026, 3, 11))
    }

    @Test func weeklyDueTodayMovesOneWeek() {
        #expect(next(.weekly, due: date(2026, 3, 10)) == day(2026, 3, 17))
    }

    @Test func overdueWeeklyKeepsItsWeekday() {
        // Due 2 days ago -> next occurrence on the same weekday.
        #expect(next(.weekly, due: date(2026, 3, 8)) == day(2026, 3, 15))
        // Due 9 days ago -> skips the missed week too.
        #expect(next(.weekly, due: date(2026, 3, 1)) == day(2026, 3, 15))
    }

    @Test func overdueByExactlyOneIntervalLandsAfterToday() {
        // Due Mar 3, +7 = Mar 10 (today), which would still be due, so step once more.
        #expect(next(.weekly, due: date(2026, 3, 3)) == day(2026, 3, 17))
    }

    @Test func biweeklyAndBimonthly() {
        #expect(next(.biweekly, due: date(2026, 3, 10)) == day(2026, 3, 24))
        #expect(next(.bimonthly, due: date(2026, 3, 10)) == day(2026, 5, 10))
    }

    @Test func monthlyDoesNotDriftAtMonthEnd() {
        let now = date(2026, 3, 30)
        let result = ReviewEngine.nextDueDateAfterCompletion(
            frequency: .monthly, currentDueDate: date(2026, 1, 31), now: now, calendar: calendar
        )
        // Jan 31 + 2 months = Mar 31, not Mar 28 (which chaining Jan 31 -> Feb 28 -> Mar 28 would give).
        #expect(result == day(2026, 3, 31))
    }

    @Test func completingBeforeDueDateAdvancesFromDueDate() {
        #expect(next(.weekly, due: date(2026, 3, 12)) == day(2026, 3, 19))
    }

    @Test func restartFromCompletionCountsFromToday() {
        let preferences = SchedulingPreferences(adjustForRating: false, overduePolicy: .restartFromCompletion)
        func next(_ frequency: Frequency, due: Date) -> Date {
            ReviewEngine.nextDueDateAfterCompletion(
                frequency: frequency, currentDueDate: due, preferences: preferences, now: now, calendar: calendar
            )
        }

        // Overdue: one interval from today instead of the old weekday.
        #expect(next(.weekly, due: date(2026, 3, 8)) == day(2026, 3, 17))
        #expect(next(.monthly, due: date(2026, 2, 20)) == day(2026, 4, 10))
        // On time: same as keeping the rhythm.
        #expect(next(.weekly, due: date(2026, 3, 10)) == day(2026, 3, 17))
    }
}

// MARK: - Rating-based scheduling

struct RatingAdjustmentTests {
    private let now = date(2026, 3, 10, hour: 18)

    private func next(
        _ frequency: Frequency,
        due: Date,
        rating: PerformanceRating,
        adjust: Bool = true
    ) -> Date {
        ReviewEngine.nextDueDateAfterCompletion(
            frequency: frequency,
            currentDueDate: due,
            rating: rating,
            preferences: SchedulingPreferences(adjustForRating: adjust, overduePolicy: .keepRhythm),
            now: now,
            calendar: calendar
        )
    }

    @Test func goodOrBetterKeepsNormalInterval() {
        for rating in [PerformanceRating.perfect, .veryGood, .good] {
            #expect(next(.weekly, due: date(2026, 3, 10), rating: rating) == day(2026, 3, 17))
        }
    }

    @Test func poorHalvesTheInterval() {
        #expect(next(.weekly, due: date(2026, 3, 10), rating: .poor) == day(2026, 3, 13))
        #expect(next(.biweekly, due: date(2026, 3, 10), rating: .poor) == day(2026, 3, 17))
        // Mar 10 -> Apr 10 is 31 days; half rounds down to 15.
        #expect(next(.monthly, due: date(2026, 3, 10), rating: .poor) == day(2026, 3, 25))
        #expect(next(.daily, due: date(2026, 3, 10), rating: .poor) == day(2026, 3, 11))
    }

    @Test func veryPoorIsDueTomorrow() {
        #expect(next(.weekly, due: date(2026, 3, 10), rating: .veryPoor) == day(2026, 3, 11))
        #expect(next(.bimonthly, due: date(2026, 3, 1), rating: .veryPoor) == day(2026, 3, 11))
    }

    @Test func poorNeverPushesReviewLater() {
        // The earlier of the rhythm date and half an interval from today (Mar 13) wins.
        // Due Mar 8: rhythm date Mar 15, so Mar 13.
        #expect(next(.weekly, due: date(2026, 3, 8), rating: .poor) == day(2026, 3, 13))
        // Due Mar 4: rhythm date Mar 11 is already sooner, so it stays.
        #expect(next(.weekly, due: date(2026, 3, 4), rating: .poor) == day(2026, 3, 11))
    }

    @Test func turningAdjustmentOffIgnoresRating() {
        #expect(next(.weekly, due: date(2026, 3, 10), rating: .veryPoor, adjust: false) == day(2026, 3, 17))
    }
}

// MARK: - Reminders

struct ReminderPlannerTests {
    private let now = date(2026, 3, 10, hour: 8)

    private func schedule(_ name: String, due: Date, isActive: Bool = true) -> ScheduleWithSurah {
        ScheduleWithSurah(
            id: UUID(), surahId: 1, surahArabicName: "", surahEnglishName: name, verseCount: 1,
            frequency: .weekly, isFullSurah: true, startPage: nil, endPage: nil,
            nextDueDate: due, isActive: isActive
        )
    }

    private func plan(_ schedules: [ScheduleWithSurah], hour: Int = 12, days: Int = 5) -> [PlannedReminder] {
        ReminderPlanner.plan(schedules: schedules, hour: hour, minute: 30, days: days, now: now, calendar: calendar)
    }

    @Test func skipsDaysWithNothingDue() {
        let reminders = plan([schedule("Al-Mulk", due: date(2026, 3, 12))])

        #expect(reminders.map(\.fireDate) == [
            date(2026, 3, 12, hour: 12).addingTimeInterval(30 * 60),
            date(2026, 3, 13, hour: 12).addingTimeInterval(30 * 60),
            date(2026, 3, 14, hour: 12).addingTimeInterval(30 * 60),
        ])
        #expect(reminders.first?.body == "Al-Mulk is due for review.")
        // If it isn't completed, later reminders call it overdue.
        #expect(reminders.last?.body == "Al-Mulk is overdue for review.")
    }

    @Test func noRemindersWithoutActiveSchedules() {
        #expect(plan([]).isEmpty)
        #expect(plan([schedule("Yasin", due: date(2026, 3, 10), isActive: false)]).isEmpty)
    }

    @Test func skipsTodayWhenReminderTimeHasPassed() {
        let reminders = plan([schedule("Yasin", due: date(2026, 3, 10))], hour: 7, days: 2)
        #expect(reminders.count == 1)
        #expect(calendar.isDate(reminders[0].fireDate, inSameDayAs: date(2026, 3, 11)))
    }

    @Test func listsNamesInDueOrderWithBadge() {
        let reminders = plan([
            schedule("Al-Kahf", due: date(2026, 3, 10)),
            schedule("Al-Mulk", due: date(2026, 3, 8)),
            schedule("Yasin", due: date(2026, 3, 9)),
            schedule("Ar-Rahman", due: date(2026, 3, 20)),
        ], days: 1)

        #expect(reminders.count == 1)
        #expect(reminders[0].body == "3 reviews due: Al-Mulk, Yasin and 1 more. 2 overdue.")
        #expect(reminders[0].badge == 3)
    }

    @Test func bodyForTwoReviews() {
        #expect(ReminderPlanner.body(names: ["Al-Mulk", "Yasin"], overdueCount: 0) == "2 reviews due: Al-Mulk and Yasin.")
    }
}

// MARK: - Due date after changing frequency

struct FrequencyChangeTests {
    private let now = date(2026, 3, 10, hour: 18)

    @Test func neverReviewedKeepsCurrentDueDate() {
        let result = ReviewEngine.dueDateAfterFrequencyChange(
            frequency: .weekly, currentDueDate: date(2026, 3, 10), lastCompletedAt: nil, now: now, calendar: calendar
        )
        #expect(result == day(2026, 3, 10))
    }

    @Test func measuresNewIntervalFromLastReview() {
        let result = ReviewEngine.dueDateAfterFrequencyChange(
            frequency: .weekly, currentDueDate: date(2026, 3, 11), lastCompletedAt: date(2026, 3, 7), now: now, calendar: calendar
        )
        #expect(result == day(2026, 3, 14))
    }

    @Test func shorterIntervalAlreadyPassedIsDueToday() {
        // Weekly reviewed 5 days ago, switched to daily: due now, not a week from the old due date.
        let result = ReviewEngine.dueDateAfterFrequencyChange(
            frequency: .daily, currentDueDate: date(2026, 3, 12), lastCompletedAt: date(2026, 3, 5), now: now, calendar: calendar
        )
        #expect(result == day(2026, 3, 10))
    }
}

// MARK: - Streaks

struct StreakTests {
    private let now = date(2026, 3, 10, hour: 18)

    private func current(_ dates: [Date]) -> Int {
        ReviewEngine.calculateCurrentStreak(sessionDates: dates, now: now, calendar: calendar)
    }

    @Test func noSessionsIsZero() {
        #expect(current([]) == 0)
        #expect(ReviewEngine.calculateLongestStreak(sessionDates: [], calendar: calendar) == 0)
    }

    @Test func sessionTodayCountsOne() {
        #expect(current([date(2026, 3, 10)]) == 1)
    }

    @Test func streakStaysAliveUntilTodayEnds() {
        // Reviewed the previous 3 days but not yet today.
        #expect(current([date(2026, 3, 9), date(2026, 3, 8), date(2026, 3, 7)]) == 3)
    }

    @Test func missedDayResetsStreak() {
        #expect(current([date(2026, 3, 8), date(2026, 3, 7)]) == 0)
        #expect(current([date(2026, 3, 10), date(2026, 3, 8), date(2026, 3, 7)]) == 1)
    }

    @Test func multipleSessionsInADayCountOnce() {
        let dates = [
            date(2026, 3, 10, hour: 8), date(2026, 3, 10, hour: 20),
            date(2026, 3, 9, hour: 7), date(2026, 3, 9, hour: 22),
        ]
        #expect(current(dates) == 2)
        #expect(ReviewEngine.calculateLongestStreak(sessionDates: dates, calendar: calendar) == 2)
    }

    @Test func longestStreakFindsBestRun() {
        let dates = [
            date(2026, 3, 1), date(2026, 3, 2), date(2026, 3, 3), date(2026, 3, 4),
            date(2026, 3, 7), date(2026, 3, 8),
        ].shuffled()
        #expect(ReviewEngine.calculateLongestStreak(sessionDates: dates, calendar: calendar) == 4)
    }
}

// MARK: - DataStore

@MainActor
struct DataStoreTests {
    private let context: NSManagedObjectContext
    private let store: DataStore

    init() {
        context = PersistenceController(inMemory: true).container.viewContext
        // Fixed preferences so tests don't depend on the simulator's saved settings.
        store = DataStore(context: context, preferences: { .default })
    }

    private func createSchedule(frequency: Frequency, nextDueDate: Date) async throws -> UUID {
        try await store.createSchedule(surahId: 1, frequency: frequency, isFullSurah: true)
        let schedule = try #require(try await store.getAllSchedules().first)
        try await store.updateSchedule(id: schedule.id, nextDueDate: nextDueDate)
        return schedule.id
    }

    private func schedule(_ id: UUID) async throws -> ScheduleWithSurah {
        try #require(try await store.getAllSchedules().first { $0.id == id })
    }

    private func daysFromToday(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: Date()))!
    }

    @Test func completingOverdueScheduleClearsOverdue() async throws {
        let id = try await createSchedule(frequency: .daily, nextDueDate: daysFromToday(-5))

        try await store.createSession(scheduleId: id, performanceRating: .good)

        let updated = try await schedule(id)
        #expect(!updated.isOverdue)
        #expect(!updated.isDueToday)
        #expect(Calendar.current.startOfDay(for: updated.nextDueDate) == daysFromToday(1))
    }

    @Test func savingUnchangedFrequencyKeepsDueDate() async throws {
        let dueDate = daysFromToday(3)
        let id = try await createSchedule(frequency: .weekly, nextDueDate: dueDate)

        try await store.updateSchedule(id: id, frequency: .weekly)

        #expect(try await schedule(id).nextDueDate == dueDate)
    }

    @Test func staleStoredStreakIsRecomputedOnRead() async throws {
        let id = try await createSchedule(frequency: .daily, nextDueDate: daysFromToday(0))
        try await store.createSession(scheduleId: id, performanceRating: .perfect)
        #expect(try await store.getStats().currentStreak == 1)

        // Simulate the only session having happened 3 days ago.
        let session = try #require(try context.fetch(SessionEntity.fetchRequest()).first)
        session.completedAt = daysFromToday(-3)
        try context.save()

        let stats = try await store.getStats()
        #expect(stats.currentStreak == 0)
        #expect(stats.longestStreak == 1)
    }

    @Test func poorRatingBringsReviewBackSooner() async throws {
        let id = try await createSchedule(frequency: .weekly, nextDueDate: daysFromToday(0))

        let completed = try await store.createSession(scheduleId: id, performanceRating: .veryPoor)

        #expect(completed.nextDueDate == daysFromToday(1))
        #expect(Calendar.current.startOfDay(for: try await schedule(id).nextDueDate) == daysFromToday(1))
    }

    @Test func undoRemovesSessionAndRestoresDueDate() async throws {
        let dueDate = daysFromToday(-2)
        let id = try await createSchedule(frequency: .weekly, nextDueDate: dueDate)

        let completed = try await store.createSession(scheduleId: id, performanceRating: .good)
        #expect(completed.previousDueDate == dueDate)
        #expect(completed.surahEnglishName == "Al-Fatiha")

        try await store.undoSession(completed)

        #expect(try await schedule(id).nextDueDate == dueDate)
        #expect(try await store.getRecentSessions().isEmpty)
        let stats = try await store.getStats()
        #expect(stats.totalSessions == 0)
        #expect(stats.currentStreak == 0)
        #expect(stats.longestStreak == 0)
        #expect(stats.lastSessionDate == nil)
    }

    @Test func undoKeepsDueDateChangedAfterCompletion() async throws {
        let id = try await createSchedule(frequency: .weekly, nextDueDate: daysFromToday(0))
        let completed = try await store.createSession(scheduleId: id, performanceRating: .good)

        let manualDate = daysFromToday(3)
        try await store.updateSchedule(id: id, nextDueDate: manualDate)
        try await store.undoSession(completed)

        #expect(try await schedule(id).nextDueDate == manualDate)
    }

    @Test func editingAndDeletingSessionsUpdatesStats() async throws {
        let id = try await createSchedule(frequency: .daily, nextDueDate: daysFromToday(0))
        try await store.createSession(scheduleId: id, performanceRating: .perfect)
        try await store.createSession(scheduleId: id, performanceRating: .perfect)
        #expect(try await store.getStats().averageRating == 5)

        let sessions = try await store.getRecentSessions()
        try await store.updateSession(id: sessions[0].id, performanceRating: .poor, notes: "Mixed up verses 3-4")

        let edited = try #require(try await store.getRecentSessions().first { $0.id == sessions[0].id })
        #expect(edited.performanceRating == .poor)
        #expect(edited.notes == "Mixed up verses 3-4")
        #expect(try await store.getStats().averageRating == 3.5)

        try await store.deleteSession(id: sessions[1].id)

        let stats = try await store.getStats()
        #expect(stats.totalSessions == 1)
        #expect(stats.averageRating == 2)
    }

    @Test func deletingScheduleRemovesItsSessionsFromStats() async throws {
        let kept = try await createSchedule(frequency: .daily, nextDueDate: daysFromToday(0))
        try await store.createSession(scheduleId: kept, performanceRating: .perfect)

        try await store.createSchedule(surahId: 2, frequency: .weekly, isFullSurah: true)
        let deleted = try #require(try await store.getAllSchedules().first { $0.surahId == 2 }).id
        try await store.createSession(scheduleId: deleted, performanceRating: .veryPoor)
        try await store.createSession(scheduleId: deleted, performanceRating: .veryPoor)
        #expect(try store.sessionCount(scheduleId: deleted) == 2)

        try await store.deleteSchedule(id: deleted)

        #expect(try store.sessionCount(scheduleId: deleted) == 0)
        let sessions = try await store.getRecentSessions()
        let stats = try await store.getStats()
        #expect(sessions.count == 1)
        #expect(stats.totalSessions == 1)
        #expect(stats.averageRating == 5)
    }

    @Test func removesOrphanedSessionsLeftByOlderVersions() async throws {
        let id = try await createSchedule(frequency: .daily, nextDueDate: daysFromToday(0))
        try await store.createSession(scheduleId: id, performanceRating: .good)

        // An older version deleted schedules without their sessions.
        let orphan = SessionEntity(context: context)
        orphan.id = UUID()
        orphan.scheduleId = UUID()
        orphan.performanceRating = PerformanceRating.veryPoor.rawValue
        orphan.completedAt = Date()
        try context.save()

        try await store.removeOrphanedSessions()

        #expect(try context.count(for: SessionEntity.fetchRequest()) == 1)
        #expect(try await store.getStats().totalSessions == 1)
    }

    @Test func clearAllDataDoesNotLeaveDeletedObjectsInContext() async throws {
        let id = try await createSchedule(frequency: .daily, nextDueDate: daysFromToday(0))
        try await store.createSession(scheduleId: id, performanceRating: .good)
        let scheduleObjectID = try #require(try context.fetch(ScheduleEntity.fetchRequest()).first).objectID

        try await store.clearAllData()

        #expect(context.registeredObject(for: scheduleObjectID) == nil)
        #expect(try await store.getAllSchedules().isEmpty)
        #expect(try await store.getRecentSessions().isEmpty)
        let stats = try await store.getStats()
        #expect(stats.totalSessions == 0)
        #expect(stats.longestStreak == 0)
    }
}

// MARK: - Surah data

struct SurahDataTests {
    private func loadSurahs() throws -> [Surah] {
        let url = try #require(Bundle.main.url(forResource: "surahs", withExtension: "json"))
        return try JSONDecoder().decode([Surah].self, from: Data(contentsOf: url))
    }

    @Test func has114SurahsWithCorrectVerseTotal() throws {
        let surahs = try loadSurahs()
        #expect(surahs.map(\.id) == Array(1...114))
        #expect(surahs.reduce(0) { $0 + $1.verseCount } == 6236)
    }

    @Test func pageRangesCoverEveryPageWithoutGaps() throws {
        let surahs = try loadSurahs()
        #expect(surahs.first?.pageStart == 1)
        #expect(surahs.last?.pageEnd == 604)

        for (surah, next) in zip(surahs, surahs.dropFirst()) {
            #expect(surah.pageStart <= surah.pageEnd, "Surah \(surah.id) has an inverted page range")
            // The next surah starts on the same page this one ends on, or the page after.
            #expect(
                next.pageStart == surah.pageEnd || next.pageStart == surah.pageEnd + 1,
                "Gap or overlap between surah \(surah.id) (ends \(surah.pageEnd)) and \(next.id) (starts \(next.pageStart))"
            )
        }
    }
}
