import Foundation
import CoreData
import Combine

@MainActor
class SchedulesViewModel: ObservableObject {
    @Published var schedules: [ScheduleWithSurah] = []
    @Published var surahs: [Surah] = []
    @Published var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published var error: String?
    /// Set when the permanent lock stops a change. It's a notice, not a failure.
    @Published var lockNotice: String?
    @Published var showSurahSelection = false
    @Published private(set) var plan: HifzPlan?
    @Published private(set) var lessons: [HifzLesson] = []
    @Published private(set) var recentReviews: [HifzReview] = []
    /// Says what moved to revision when a plan ends.
    @Published var planNotice: String?

    var hifzToday: HifzToday? {
        plan.map { HifzToday(plan: $0, lessons: lessons, reviews: recentReviews) }
    }
    
    private let dataStore: DataStore
    private let isHeldByLock: @MainActor (ScheduleWithSurah) -> Bool
    private let isPlanHeldByLock: @MainActor (HifzToday) -> Bool
    
    init(
        dataStore: DataStore = DataStore(),
        isHeldByLock: @escaping @MainActor (ScheduleWithSurah) -> Bool = { AppLockManager.shared.holds($0) },
        isPlanHeldByLock: @escaping @MainActor (HifzToday) -> Bool = { AppLockManager.shared.holdsPlan($0) }
    ) {
        self.dataStore = dataStore
        self.isHeldByLock = isHeldByLock
        self.isPlanHeldByLock = isPlanHeldByLock
    }

    /// While a permanent lock's settings are fixed and today's lesson or recent review is due, the
    /// plan can't be paused or ended, or today taken off its lesson days. Says so and returns true.
    private func blocksPlanChange() -> Bool {
        guard let today = hifzToday, isPlanHeldByLock(today) else { return false }
        lockNotice = LockError.planHeld.localizedDescription
        return true
    }
    
    /// While a permanent lock's settings are fixed, a passage that's due can't be paused, deleted
    /// or rescheduled: any of those would unlock the apps without the review being done. Says so
    /// and returns true.
    func blocksChange(to schedule: ScheduleWithSurah) -> Bool {
        guard isHeldByLock(schedule) else { return false }
        lockNotice = "\(schedule.surahEnglishName) is due. While the Revision Lock is permanent, a passage that’s due can’t be paused, deleted or rescheduled. Log its review first, or wait for your weekly change window."
        return true
    }
    
    private func blocksChange(toScheduleWithId id: UUID) -> Bool {
        guard let schedule = schedules.first(where: { $0.id == id }) else { return false }
        return blocksChange(to: schedule)
    }
    
    func loadData() async {
        // Prevent multiple simultaneous loads
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        
        do {
            async let scheduleData = dataStore.getAllSchedules()
            async let surahData = dataStore.getAllSurahs()
            async let planData = dataStore.getCurrentPlan()
            async let lessonData = dataStore.getAllLessons()
            async let reviewData = dataStore.getAllRecentReviews()
            
            schedules = try await scheduleData
            surahs = try await surahData
            plan = try await planData
            lessons = try await lessonData
            recentReviews = try await reviewData
        } catch {
            self.error = "Failed to load schedules: \(error.localizedDescription)"
        }
        
        isLoading = false
        hasLoaded = true
    }
    
    func createSchedule(
        surahId: Int,
        frequency: Frequency,
        isFullSurah: Bool,
        startPage: Int? = nil,
        endPage: Int? = nil,
        startsOn: Date = Date()
    ) async throws {
        try await dataStore.createSchedule(
            surahId: Int16(surahId),
            frequency: frequency,
            isFullSurah: isFullSurah,
            startPage: startPage.map { Int16($0) },
            endPage: endPage.map { Int16($0) },
            startsOn: startsOn
        )
        await loadData()
    }
    
    func updateSchedule(id: UUID, frequency: Frequency?, nextDueDate: Date?, isActive: Bool?) async {
        guard !blocksChange(toScheduleWithId: id) else { return }
        do {
            try await dataStore.updateSchedule(
                id: id,
                frequency: frequency,
                nextDueDate: nextDueDate,
                isActive: isActive
            )
            await loadData()
        } catch {
            self.error = "Failed to update schedule: \(error.localizedDescription)"
        }
    }
    
    func deleteSchedule(id: UUID) async {
        guard !blocksChange(toScheduleWithId: id) else { return }
        do {
            try await dataStore.deleteSchedule(id: id)
            await loadData()
        } catch {
            self.error = "Failed to delete schedule: \(error.localizedDescription)"
        }
    }
    
    func sessionCount(scheduleId: UUID) -> Int {
        (try? dataStore.sessionCount(scheduleId: scheduleId)) ?? 0
    }
    
    func toggleScheduleActive(id: UUID, currentState: Bool) async {
        await updateSchedule(id: id, frequency: nil, nextDueDate: nil, isActive: !currentState)
    }
    
    func updateScheduleFrequency(id: UUID, frequency: Frequency) async {
        await updateSchedule(id: id, frequency: frequency, nextDueDate: nil, isActive: nil)
    }

    // MARK: - Memorization plan

    func createPlan(_ draft: HifzPlanDraft) async throws {
        try await dataStore.createPlan(
            title: draft.title, startPage: draft.startPage, endPage: draft.endPage, halvesPerDay: draft.halvesPerDay,
            lessonWeekdays: draft.lessonWeekdays, recentReviewCount: draft.recentReviewCount,
            revisionFrequency: draft.revisionFrequency
        )
        await loadData()
    }

    /// Saves a new pace for the current plan.
    func savePlan(_ draft: HifzPlanDraft) async throws {
        guard var plan else { throw DataStoreError.planNotFound }
        let today = Calendar.current.component(.weekday, from: Date())
        if HifzPlan.weekdayIsSet(today, in: plan.lessonWeekdays),
           !HifzPlan.weekdayIsSet(today, in: draft.lessonWeekdays),
           let hifzToday, isPlanHeldByLock(hifzToday) {
            throw LockError.planHeld
        }
        plan.halvesPerDay = draft.halvesPerDay
        plan.lessonWeekdays = draft.lessonWeekdays
        plan.recentReviewCount = draft.recentReviewCount
        plan.revisionFrequency = draft.revisionFrequency
        try await dataStore.updatePlan(plan)
        await loadData()
    }

    func setPlanActive(_ isActive: Bool) async {
        guard var plan else { return }
        guard isActive || !blocksPlanChange() else { return }
        plan.isActive = isActive
        do {
            try await dataStore.updatePlan(plan)
            await loadData()
        } catch {
            self.error = "Failed to update your plan: \(error.localizedDescription)"
        }
    }

    /// Ends the plan, moving everything memorized into revision.
    func endPlan() async {
        guard let plan, !blocksPlanChange() else { return }
        do {
            let moved = try await dataStore.endPlan(id: plan.id)
            planNotice = moved?.message ?? "\(plan.title) has ended."
            await loadData()
        } catch {
            self.error = "Failed to end your plan: \(error.localizedDescription)"
        }
    }
}
