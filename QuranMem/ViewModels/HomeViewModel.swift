import Foundation
import CoreData
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var todaySchedules: [ScheduleWithSurah] = []
    @Published var calendarSchedules: [Date: [ScheduleWithSurah]] = [:]
    @Published private(set) var allSchedules: [ScheduleWithSurah] = []
    @Published private(set) var sessions: [SessionWithSchedule] = []
    @Published private(set) var surahs: [Surah] = []
    @Published var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var loadFailed = false
    @Published var error: String?
    /// The most recently saved review or lesson, while it can still be undone.
    @Published var lastCompleted: UndoableAction?
    /// The memorization plan that's under way, paused or not.
    @Published private(set) var plan: HifzPlan?
    @Published private(set) var lessons: [HifzLesson] = []
    @Published private(set) var recentReviews: [HifzReview] = []
    /// Set when today's load moved settled lessons into revision.
    @Published var movedToRevision: MovedToRevision?
    
    var dailySummary: DailyReviewSummary {
        DailyReviewSummary(schedules: allSchedules, sessions: sessions)
    }

    var hifzToday: HifzToday? {
        plan.map { HifzToday(plan: $0, lessons: lessons, reviews: recentReviews) }
    }

    /// The latest note from a recent review of the current plan.
    var previousRecentReviewNote: String? {
        recentReviews
            .filter { $0.planId == plan?.id }
            .sorted { $0.completedAt > $1.completedAt }
            .lazy
            .compactMap { $0.notes?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    var previousNotes: [UUID: String] {
        var notes: [UUID: String] = [:]
        for session in sessions.sorted(by: { $0.completedAt > $1.completedAt }) {
            if notes[session.scheduleId] == nil,
               let note = session.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                notes[session.scheduleId] = note
            }
        }
        return notes
    }

    private let dataStore: DataStore
    private let notificationManager: NotificationManager
    private let isPlanHeldByLock: @MainActor (HifzToday) -> Bool
    
    init(
        dataStore: DataStore = DataStore(),
        notificationManager: NotificationManager = .shared,
        isPlanHeldByLock: @escaping @MainActor (HifzToday) -> Bool = { AppLockManager.shared.holdsPlan($0) }
    ) {
        self.dataStore = dataStore
        self.notificationManager = notificationManager
        self.isPlanHeldByLock = isPlanHeldByLock
    }
    
    func loadData() async {
        // Prevent multiple simultaneous loads
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        
        // Settled lessons move to revision before today's queue is built. A failure here
        // shouldn't keep the rest of Home from loading; the next load tries again.
        do {
            if let moved = try await dataStore.graduateReadyLessons() {
                movedToRevision = moved
            }
        } catch {
            print("Error moving lessons to revision: \(error)")
        }

        do {
            let schedules = try await dataStore.getAllSchedules()
            let sessions = try await dataStore.getRecentSessions()
            let surahs = try await dataStore.getAllSurahs()
            let plan = try await dataStore.getCurrentPlan()
            let lessons = try await dataStore.getAllLessons()
            let recentReviews = try await dataStore.getAllRecentReviews()
            // Publish one complete snapshot only after every fetch succeeds.
            self.allSchedules = schedules
            self.sessions = sessions
            self.surahs = surahs
            self.plan = plan
            self.lessons = lessons
            self.recentReviews = recentReviews
            self.todaySchedules = DailyReviewSummary(schedules: schedules, sessions: sessions).remaining
            calendarSchedules = calculateCalendarSchedules(schedules: schedules)
            hasLoaded = true
            loadFailed = false

            updateBadgeCount()
        } catch {
            loadFailed = true
            self.error = "Failed to load data: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func calculateCalendarSchedules(schedules: [ScheduleWithSurah]) -> [Date: [ScheduleWithSurah]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let twoWeeksFromNow = calendar.date(byAdding: .day, value: 14, to: today) ?? today
        
        var result: [Date: [ScheduleWithSurah]] = [:]
        
        // Pre-allocate dictionary capacity for better performance
        result.reserveCapacity(15)
        
        for schedule in schedules where schedule.isActive {
            let scheduleDueDate = calendar.startOfDay(for: schedule.nextDueDate)
            var currentDate = scheduleDueDate
            
            // If the next due date is in the past, show it on today's date for visibility
            let isOverdue = scheduleDueDate < today
            if isOverdue {
                currentDate = today
            }
            var isFirstOccurrence = true
            
            // Limit iterations to prevent infinite loops
            var iterationCount = 0
            let maxIterations = 100
            
            // Generate all due dates for this schedule within the next 2 weeks
            while currentDate <= twoWeeksFromNow && iterationCount < maxIterations {
                iterationCount += 1
                
                let dateKey = calendar.startOfDay(for: currentDate)
                
                if result[dateKey] == nil {
                    result[dateKey] = []
                }
                
                // Create a copy of the schedule with this due date. An overdue
                // review is pinned to today's cell so it stays visible, but it
                // keeps its real due date — otherwise the copy reports itself as
                // on time and the calendar loses the one fact worth showing.
                let dueDateForCell = (isOverdue && isFirstOccurrence) ? scheduleDueDate : dateKey
                let scheduleForDate = ScheduleWithSurah(
                    id: schedule.id,
                    surahId: schedule.surahId,
                    surahArabicName: schedule.surahArabicName,
                    surahEnglishName: schedule.surahEnglishName,
                    verseCount: schedule.verseCount,
                    frequency: schedule.frequency,
                    isFullSurah: schedule.isFullSurah,
                    startPage: schedule.startPage,
                    endPage: schedule.endPage,
                    nextDueDate: dueDateForCell,
                    isActive: schedule.isActive,
                    hasBeenReviewed: schedule.hasBeenReviewed,
                    hifzPlanId: schedule.hifzPlanId
                )
                
                result[dateKey]?.append(scheduleForDate)
                isFirstOccurrence = false
                
                // Calculate next due date based on frequency
                if let days = schedule.frequency.daysToAdd {
                    guard let nextDate = calendar.date(byAdding: .day, value: days, to: currentDate) else { break }
                    currentDate = nextDate
                } else if let months = schedule.frequency.monthsToAdd {
                    guard let nextDate = calendar.date(byAdding: .month, value: months, to: currentDate) else { break }
                    currentDate = nextDate
                } else {
                    // No valid frequency, only show once
                    break
                }
            }
        }
        
        return result
    }
    
    @discardableResult
    func completeSession(scheduleId: UUID, performanceRating: PerformanceRating, notes: String?) async throws -> CompletedSession {
        let completed = try await dataStore.createSession(
            scheduleId: scheduleId,
            performanceRating: performanceRating,
            notes: notes
        )
        lastCompleted = .revision(completed)
        await loadData()
        return completed
    }

    func createSchedule(surahId: Int, frequency: Frequency, isFullSurah: Bool, startPage: Int?, endPage: Int?, startsOn: Date) async throws {
        try await dataStore.createSchedule(
            surahId: Int16(surahId), frequency: frequency, isFullSurah: isFullSurah,
            startPage: startPage.map { Int16($0) }, endPage: endPage.map { Int16($0) }, startsOn: startsOn
        )
        await loadData()
    }

    func undoLastSession() async {
        guard let action = lastCompleted else { return }
        do {
            switch action {
            case .revision(let completed):
                try await dataStore.undoSession(completed)
            case .lesson(let ids, _):
                try await dataStore.undoMemorize(lessonIds: ids)
            case .recentReview(let id, _):
                try await dataStore.deleteRecentReview(id: id)
            }
            lastCompleted = nil
            await loadData()
        } catch {
            self.error = "Failed to undo: \(error.localizedDescription)"
        }
    }
    
    func dismissUndo(for action: UndoableAction) {
        if lastCompleted == action {
            lastCompleted = nil
        }
    }

    // MARK: - Memorization plan

    /// Starts a plan. With `replacingCurrent`, a plan still under way is ended first, its unsettled
    /// portions moving to revision.
    func createPlan(_ draft: HifzPlanDraft, replacingCurrent: Bool = false) async throws {
        if replacingCurrent, let plan {
            if let hifzToday, isPlanHeldByLock(hifzToday) { throw LockError.planHeld }
            movedToRevision = try await dataStore.endPlan(id: plan.id)
        }
        try await dataStore.createPlan(
            title: draft.title, startPage: draft.startPage, endPage: draft.endPage, halvesPerDay: draft.halvesPerDay,
            lessonWeekdays: draft.lessonWeekdays, recentReviewCount: draft.recentReviewCount,
            revisionFrequency: draft.revisionFrequency
        )
        await loadData()
    }

    /// The surahs on these pages, in mushaf order: "Al-Haqqah, Al-Ma'arij".
    func surahNames(onPages pages: [Int]) -> String {
        var ids = Set<Int>()
        return Set(pages).sorted()
            .flatMap { QuranPages.surahs(onPage: $0, in: surahs) }
            .filter { ids.insert($0.id).inserted }
            .map(\.englishName)
            .joined(separator: ", ")
    }

    func memorize(_ halves: [HalfPage], notes: String?) async throws {
        guard let plan else { throw DataStoreError.planNotFound }
        let ids = try await dataStore.memorize(halves, planId: plan.id, notes: notes)
        lastCompleted = .lesson(ids: ids, description: halves.portionDescription)
        await loadData()
    }

    func logRecentReview(_ block: HifzToday.RecentBlock, rating: PerformanceRating, notes: String?) async throws {
        guard let plan else { throw DataStoreError.planNotFound }
        let id = try await dataStore.logRecentReview(planId: plan.id, block: block, performanceRating: rating, notes: notes)
        lastCompleted = .recentReview(id: id, description: block.halves.pageRangeDescription)
        await loadData()
    }

    func setPlanActive(_ isActive: Bool) async {
        guard var plan else { return }
        plan.isActive = isActive
        do {
            try await dataStore.updatePlan(plan)
            await loadData()
        } catch {
            self.error = "Failed to update your plan: \(error.localizedDescription)"
        }
    }

    /// Ends the current plan, moving everything memorized into revision.
    func endPlan() async {
        guard let plan else { return }
        do {
            movedToRevision = try await dataStore.endPlan(id: plan.id)
            await loadData()
        } catch {
            self.error = "Failed to end your plan: \(error.localizedDescription)"
        }
    }
    
    private func updateBadgeCount() {
        let count = todaySchedules.filter { $0.isDueToday }.count + (hifzToday?.pendingCount ?? 0)
        notificationManager.updateBadgeCount(count)
    }
}
