import CoreData
import Foundation
import Testing
@testable import QuranMem

private let reviewCalendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "UTC")!
    return value
}()
private let reviewToday = reviewCalendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 12))!
private func reviewDate(_ offset: Int) -> Date {
    reviewCalendar.date(byAdding: .day, value: offset, to: reviewToday)!
}
private func passage(id: UUID = UUID(), offset: Int = 0, active: Bool = true) -> ScheduleWithSurah {
    ScheduleWithSurah(id: id, surahId: 1, surahArabicName: "الفاتحة", surahEnglishName: "Al-Fatiha", verseCount: 7,
                      frequency: .daily, isFullSurah: true, startPage: nil, endPage: nil, nextDueDate: reviewDate(offset), isActive: active)
}
private func log(_ schedule: ScheduleWithSurah, offset: Int = 0) -> SessionWithSchedule {
    SessionWithSchedule(id: UUID(), scheduleId: schedule.id, surahArabicName: schedule.surahArabicName,
                        surahEnglishName: schedule.surahEnglishName, performanceRating: .good,
                        completedAt: reviewDate(offset), notes: nil, frequency: .daily)
}
private func summary(_ schedules: [ScheduleWithSurah], _ sessions: [SessionWithSchedule] = []) -> DailyReviewSummary {
    DailyReviewSummary(schedules: schedules, sessions: sessions, now: reviewToday, calendar: reviewCalendar)
}

struct DailyReviewSummaryTests {
    @Test func emptyLibraryIsGettingStarted() {
        #expect(summary([]).state == .gettingStarted)
        #expect(summary([]).totalCount == 0)
    }

    @Test func quietDayHasNextActiveDateAndNoFalseCompletion() {
        let state = summary([passage(offset: 3), passage(offset: 1, active: false)])
        #expect(state.state == .quietDay)
        #expect(state.completedCount == 0)
        #expect(state.nextReviewDate == reviewDate(3))
    }

    @Test func pausedLibraryDoesNotPromiseAFutureReview() {
        let state = summary([passage(active: false)])
        #expect(state.state == .paused)
        #expect(state.nextReviewDate == nil)
    }

    @Test func overduePassagesLeadAndPausedPassagesAreExcluded() {
        let today = passage()
        let overdue = passage(offset: -4)
        let state = summary([today, passage(offset: -6, active: false), overdue])
        #expect(state.state == .reviewsDue)
        #expect(state.remaining.map(\.id) == [overdue.id, today.id])
        #expect(state.totalCount == 2)
    }

    @Test func duplicateLogsAndYesterdaysLogsDoNotInflateProgress() {
        let done = passage(offset: 1)
        let yesterday = passage(offset: 2)
        let state = summary([done, yesterday, passage()], [log(done), log(done), log(yesterday, offset: -1)])
        #expect(state.completedCount == 1)
        #expect(state.totalCount == 2)
        #expect(state.state == .reviewsDue)
    }

    @Test func finalSavedPassageFinishesTheDay() {
        let done = passage(offset: 1)
        let state = summary([done], [log(done)])
        #expect(state.state == .finished)
        #expect(state.completedCount == state.totalCount)
    }

    @Test func manuallyReopenedPassageIsStillDue() {
        let due = passage()
        let state = summary([due], [log(due)])
        #expect(state.completedCount == 0)
        #expect(state.remaining.count == 1)
    }

    @Test func nextDayStartsWithFreshCounts() {
        let done = passage(offset: 1)
        let state = DailyReviewSummary(schedules: [done], sessions: [log(done)], now: reviewDate(1), calendar: reviewCalendar)
        #expect(state.completedCount == 0)
        #expect(state.state == .reviewsDue)
    }
}

@MainActor
struct ReviewQueueTests {
    private func completion(_ id: UUID) -> CompletedSession {
        CompletedSession(sessionId: UUID(), scheduleId: id, surahEnglishName: "Al-Fatiha", previousDueDate: reviewToday, nextDueDate: reviewDate(1))
    }

    @Test func successAdvancesResetsDraftAndFinishesOnlyAfterLastSave() async {
        let first = passage()
        let second = passage()
        let queue = ReviewQueueViewModel(schedules: [first, second])
        queue.showRating()
        queue.selectedRating = .good
        queue.notes = "  Check verse 3  "
        await queue.submit { id, rating, notes in
            #expect(id == first.id)
            #expect(rating == .good)
            #expect(notes == "Check verse 3")
            return completion(id)
        }
        #expect(queue.current?.id == second.id)
        #expect(queue.selectedRating == nil)
        #expect(queue.notes.isEmpty)
        #expect(!queue.isRating)
        #expect(!queue.isFinished)
        queue.showRating()
        queue.selectedRating = .perfect
        await queue.submit { id, _, notes in
            #expect(notes == nil)
            return completion(id)
        }
        #expect(queue.isFinished)
        #expect(queue.completions.count == 2)
        #expect(queue.nextReviewDate == reviewDate(1))
    }

    @Test func failedSavePreservesPassageAndDraftForRetry() async {
        let first = passage()
        let queue = ReviewQueueViewModel(schedules: [first])
        queue.showRating()
        queue.selectedRating = .poor
        queue.notes = "Repeat ending"
        await queue.submit { _, _, _ in throw DataStoreError.scheduleNotFound }
        #expect(queue.current?.id == first.id)
        #expect(queue.isRating)
        #expect(queue.selectedRating == .poor)
        #expect(queue.notes == "Repeat ending")
        #expect(queue.completions.isEmpty)
        #expect(queue.error != nil)
        #expect(!queue.isSubmitting)
        await queue.submit { id, _, _ in completion(id) }
        #expect(queue.isFinished)
        #expect(queue.completions.count == 1)
        #expect(queue.error == nil)
    }

    @Test func missingRatingCannotSave() async {
        let queue = ReviewQueueViewModel(schedules: [passage()])
        await queue.submit { id, _, _ in
            Issue.record("A rating is required before saving")
            return completion(id)
        }
        #expect(queue.index == 0)
    }

    @Test func duplicateTapDuringSaveDoesNotCreateAnotherSession() async {
        let queue = ReviewQueueViewModel(schedules: [passage()])
        queue.selectedRating = .good
        await queue.submit { id, _, _ in
            await queue.submit { duplicateID, _, _ in
                Issue.record("Submission already in progress")
                return completion(duplicateID)
            }
            return completion(id)
        }
        #expect(queue.completions.count == 1)
    }

    @Test func returningToPassageKeepsDraft() {
        let queue = ReviewQueueViewModel(schedules: [passage()])
        queue.showRating()
        queue.selectedRating = .good
        queue.notes = "Remember the ending"
        queue.showPassage()
        #expect(queue.hasDraft)
        #expect(queue.selectedRating == .good)
    }
}

@MainActor
struct HomeReviewPersistenceTests {
    @Test func savedProgressReloadsAndUndoRestoresDuePassage() async throws {
        let context = PersistenceController(inMemory: true).container.viewContext
        let store = DataStore(context: context, preferences: { .default })
        try await store.createSchedule(surahId: 1, frequency: .daily, isFullSurah: true)
        let home = HomeViewModel(dataStore: store)
        await home.loadData()
        #expect(home.dailySummary.totalCount == 1)
        let id = try #require(home.todaySchedules.first?.id)
        try await home.completeSession(scheduleId: id, performanceRating: .good, notes: "Check the ending")
        #expect(home.dailySummary.state == .finished)
        let reopened = HomeViewModel(dataStore: store)
        await reopened.loadData()
        #expect(reopened.dailySummary.completedCount == 1)
        #expect(reopened.previousNotes[id] == "Check the ending")
        await home.undoLastSession()
        #expect(home.dailySummary.state == .reviewsDue)
        #expect(home.dailySummary.completedCount == 0)
        #expect(home.todaySchedules.first?.id == id)
    }
}

private final class FailingReviewSaveContext: NSManagedObjectContext, @unchecked Sendable {
    var failNextSave = false
    override func save() throws {
        if failNextSave {
            failNextSave = false
            throw NSError(domain: "ReviewSaveTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Storage unavailable"])
        }
        try super.save()
    }
}

@MainActor
struct ReviewSaveRecoveryTests {
    @Test func failedWriteRollsBackSessionAndDueDateBeforeRetry() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = FailingReviewSaveContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = persistence.container.persistentStoreCoordinator
        let store = DataStore(context: context, preferences: { .default })
        try await store.createSchedule(surahId: 1, frequency: .daily, isFullSurah: true)
        let original = try #require(try await store.getAllSchedules().first)
        context.failNextSave = true
        do {
            try await store.createSession(scheduleId: original.id, performanceRating: .good)
            Issue.record("The injected storage failure should throw")
        } catch {
            #expect(!context.hasChanges)
        }
        #expect(try await store.getRecentSessions().isEmpty)
        #expect(try await store.getAllSchedules().first?.nextDueDate == original.nextDueDate)
        try await store.createSession(scheduleId: original.id, performanceRating: .good)
        #expect(try await store.getRecentSessions().count == 1)
        #expect(try await store.getStats().totalSessions == 1)
    }

    @Test func failedScheduleCreationCanRetryWithoutDuplicates() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = FailingReviewSaveContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = persistence.container.persistentStoreCoordinator
        let store = DataStore(context: context)
        context.failNextSave = true
        do {
            try await store.createSchedule(surahId: 1, frequency: .daily, isFullSurah: true)
            Issue.record("The injected storage failure should throw")
        } catch {
            #expect(!context.hasChanges)
        }
        #expect(try await store.getAllSchedules().isEmpty)
        try await store.createSchedule(surahId: 1, frequency: .daily, isFullSurah: true)
        #expect(try await store.getAllSchedules().count == 1)
    }
}
