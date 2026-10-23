import CoreData
import Foundation

enum DataStoreError: LocalizedError {
    case scheduleNotFound
    case sessionNotFound
    case planNotFound
    case planAlreadyActive

    var errorDescription: String? {
        switch self {
        case .scheduleNotFound: return "The schedule no longer exists."
        case .sessionNotFound: return "The session no longer exists."
        case .planNotFound: return "The memorization plan no longer exists."
        case .planAlreadyActive: return "You already have a memorization plan. End it before starting another."
        }
    }
}

// Main actor because every operation uses the view context, which belongs to the main queue.
// Without this, `async` methods run on the global executor and touch Core Data off the main thread.
@MainActor
class DataStore: ObservableObject {
    private let viewContext: NSManagedObjectContext
    private let preferences: @Sendable () -> SchedulingPreferences

    // Only stores its arguments, so it's safe to create from any context (e.g. default arguments).
    nonisolated init(
        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext,
        preferences: @escaping @Sendable () -> SchedulingPreferences = { SchedulingPreferences.load() }
    ) {
        self.viewContext = context
        self.preferences = preferences
    }

    // MARK: - Surah Operations

    func getAllSurahs() async throws -> [Surah] {
        let request: NSFetchRequest<SurahEntity> = SurahEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SurahEntity.id, ascending: true)]

        let entities = try viewContext.fetch(request)
        return entities.map { $0.toStruct() }
    }

    func getSurah(id: Int16) async throws -> SurahEntity? {
        let request: NSFetchRequest<SurahEntity> = SurahEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %d", id)
        request.fetchLimit = 1

        return try viewContext.fetch(request).first
    }

    private func surahsById() throws -> [Int16: SurahEntity] {
        let surahs = try viewContext.fetch(SurahEntity.fetchRequest())
        return Dictionary(surahs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Schedule Operations

    func getAllSchedules() async throws -> [ScheduleWithSurah] {
        let request: NSFetchRequest<ScheduleEntity> = ScheduleEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ScheduleEntity.nextDueDate, ascending: true)]

        let schedules = try viewContext.fetch(request)
        let surahs = try surahsById()
        let reviewed = try reviewedScheduleIds()

        return schedules.compactMap { schedule in
            surahs[schedule.surahId].map {
                schedule.toScheduleWithSurah(surah: $0, hasBeenReviewed: schedule.id.map(reviewed.contains) ?? false)
            }
        }
    }

    private func reviewedScheduleIds() throws -> Set<UUID> {
        let request = NSFetchRequest<NSDictionary>(entityName: "SessionEntity")
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["scheduleId"]
        request.returnsDistinctResults = true
        return Set(try viewContext.fetch(request).compactMap { $0["scheduleId"] as? UUID })
    }

    func getTodaySchedules() async throws -> [ScheduleWithSurah] {
        let allSchedules = try await getAllSchedules()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return allSchedules.filter { schedule in
            guard schedule.isActive else { return false }
            let scheduleDate = calendar.startOfDay(for: schedule.nextDueDate)
            // Include today's tasks and overdue tasks
            return scheduleDate <= today
        }
    }

    func createSchedule(
        surahId: Int16,
        frequency: Frequency,
        isFullSurah: Bool,
        startPage: Int16? = nil,
        endPage: Int16? = nil,
        startsOn: Date = Date(),
        now: Date = Date()
    ) async throws {
        let schedule = ScheduleEntity(context: viewContext)
        schedule.id = UUID()
        schedule.surahId = surahId
        schedule.frequency = frequency.rawValue
        schedule.isFullSurah = isFullSurah
        schedule.startPage = startPage ?? 0
        schedule.endPage = endPage ?? 0
        // The first review is due on the start date; a start of today (or earlier) is due now.
        schedule.nextDueDate = max(now, Calendar.current.startOfDay(for: startsOn))
        schedule.isActive = true
        schedule.createdAt = now
        schedule.updatedAt = now

        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            throw error
        }
    }

    func updateSchedule(
        id: UUID,
        frequency: Frequency? = nil,
        nextDueDate: Date? = nil,
        isActive: Bool? = nil
    ) async throws {
        guard let schedule = try fetchSchedule(id: id) else { return }

        if let frequency = frequency, frequency.rawValue != schedule.frequency {
            schedule.frequency = frequency.rawValue
            // Only recalculate next due date if no manual date is provided
            if nextDueDate == nil {
                schedule.nextDueDate = ReviewEngine.dueDateAfterFrequencyChange(
                    frequency: frequency,
                    currentDueDate: schedule.nextDueDate ?? Date(),
                    lastCompletedAt: try lastSessionDate(scheduleId: id)
                )
            }
        }
        if let nextDueDate = nextDueDate {
            schedule.nextDueDate = nextDueDate
        }
        if let isActive = isActive {
            schedule.isActive = isActive
        }

        schedule.updatedAt = Date()
        try viewContext.save()
    }

    /// Deletes the schedule together with its sessions, so stats and history stay consistent.
    func deleteSchedule(id: UUID) async throws {
        guard let schedule = try fetchSchedule(id: id) else { return }

        for session in try fetchSessions(scheduleId: id) {
            viewContext.delete(session)
        }
        viewContext.delete(schedule)

        try recalculateStats()
        try viewContext.save()
    }

    func sessionCount(scheduleId: UUID) throws -> Int {
        let request: NSFetchRequest<SessionEntity> = SessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "scheduleId == %@", scheduleId as CVarArg)
        return try viewContext.count(for: request)
    }

    private func fetchSchedule(id: UUID) throws -> ScheduleEntity? {
        let request: NSFetchRequest<ScheduleEntity> = ScheduleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        return try viewContext.fetch(request).first
    }

    // MARK: - Session Operations

    /// Saves the session and moves the schedule to its next due date.
    /// Returns what's needed to undo it with `undoSession(_:)`.
    @discardableResult
    func createSession(
        scheduleId: UUID,
        performanceRating: PerformanceRating,
        notes: String? = nil,
        now: Date = Date()
    ) async throws -> CompletedSession {
        guard let schedule = try fetchSchedule(id: scheduleId) else {
            throw DataStoreError.scheduleNotFound
        }

        let surahName = try await getSurah(id: schedule.surahId)?.englishName ?? ""
        do {
            let sessionId = UUID()
            let session = SessionEntity(context: viewContext)
            session.id = sessionId
            session.scheduleId = scheduleId
            session.performanceRating = performanceRating.rawValue
            session.completedAt = now
            session.notes = notes

            let frequency = Frequency(rawValue: schedule.frequency ?? "daily") ?? .daily
            let previousDueDate = schedule.nextDueDate ?? now
            let nextDueDate = ReviewEngine.nextDueDateAfterCompletion(
                frequency: frequency,
                currentDueDate: previousDueDate,
                rating: performanceRating,
                preferences: preferences(),
                now: now
            )
            schedule.nextDueDate = nextDueDate
            schedule.updatedAt = now

            try recalculateStats(now: now)
            try viewContext.save()

            return CompletedSession(
                sessionId: sessionId,
                scheduleId: scheduleId,
                surahEnglishName: surahName,
                previousDueDate: previousDueDate,
                nextDueDate: nextDueDate
            )
        } catch {
            viewContext.rollback()
            throw error
        }
    }

    /// Removes a just-completed session and puts the schedule back on its previous due date,
    /// unless the schedule's date has been changed since.
    func undoSession(_ completed: CompletedSession) async throws {
        guard let session = try fetchSession(id: completed.sessionId) else {
            throw DataStoreError.sessionNotFound
        }
        viewContext.delete(session)

        if let schedule = try fetchSchedule(id: completed.scheduleId),
           schedule.nextDueDate == completed.nextDueDate {
            schedule.nextDueDate = completed.previousDueDate
            schedule.updatedAt = Date()
        }

        try recalculateStats()
        try viewContext.save()
    }

    /// Edits a past session's rating and notes. Schedule dates are left as they are.
    func updateSession(id: UUID, performanceRating: PerformanceRating, notes: String?) async throws {
        guard let session = try fetchSession(id: id) else {
            throw DataStoreError.sessionNotFound
        }

        session.performanceRating = performanceRating.rawValue
        session.notes = notes

        try recalculateStats()
        try viewContext.save()
    }

    /// Deletes a past session from history. Schedule dates are left as they are.
    func deleteSession(id: UUID) async throws {
        guard let session = try fetchSession(id: id) else { return }

        viewContext.delete(session)

        try recalculateStats()
        try viewContext.save()
    }

    func getRecentSessions(limit: Int? = nil) async throws -> [SessionWithSchedule] {
        let request: NSFetchRequest<SessionEntity> = SessionEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SessionEntity.completedAt, ascending: false)]
        if let limit = limit {
            request.fetchLimit = limit
        }

        let sessions = try viewContext.fetch(request)
        let schedules = try viewContext.fetch(ScheduleEntity.fetchRequest())
        let schedulesById = Dictionary(
            schedules.compactMap { schedule in schedule.id.map { ($0, schedule) } },
            uniquingKeysWith: { first, _ in first }
        )
        let surahs = try surahsById()

        return sessions.compactMap { session in
            guard let scheduleId = session.scheduleId,
                  let schedule = schedulesById[scheduleId],
                  let surah = surahs[schedule.surahId] else {
                return nil
            }
            return session.toSessionWithSchedule(surah: surah, schedule: schedule)
        }
    }

    func getAllSessions() async throws -> [SessionEntity] {
        try fetchAllSessions()
    }

    /// Removes sessions whose schedule no longer exists. Older versions of the app left these
    /// behind when a schedule was deleted; they were hidden from history but still counted in stats.
    func removeOrphanedSessions() async throws {
        let scheduleIds = Set(try viewContext.fetch(ScheduleEntity.fetchRequest()).compactMap(\.id))
        let orphans = try fetchAllSessions().filter { session in
            guard let scheduleId = session.scheduleId else { return true }
            return !scheduleIds.contains(scheduleId)
        }

        guard !orphans.isEmpty else { return }

        orphans.forEach(viewContext.delete)
        try recalculateStats()
        try viewContext.save()
    }

    private func fetchSession(id: UUID) throws -> SessionEntity? {
        let request: NSFetchRequest<SessionEntity> = SessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        return try viewContext.fetch(request).first
    }

    private func fetchSessions(scheduleId: UUID) throws -> [SessionEntity] {
        let request: NSFetchRequest<SessionEntity> = SessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "scheduleId == %@", scheduleId as CVarArg)
        return try viewContext.fetch(request)
    }

    private func fetchAllSessions() throws -> [SessionEntity] {
        let request: NSFetchRequest<SessionEntity> = SessionEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SessionEntity.completedAt, ascending: false)]
        return try viewContext.fetch(request)
    }

    private func lastSessionDate(scheduleId: UUID) throws -> Date? {
        let request: NSFetchRequest<SessionEntity> = SessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "scheduleId == %@", scheduleId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SessionEntity.completedAt, ascending: false)]
        request.fetchLimit = 1

        return try viewContext.fetch(request).first?.completedAt
    }

    // MARK: - Memorization Plan Operations

    /// The plan that hasn't finished or been ended, paused or not. There's at most one.
    func getCurrentPlan() async throws -> HifzPlan? {
        try fetchCurrentPlan()?.toStruct()
    }

    /// What the current plan asks for today, or nil without a plan.
    func getHifzToday(now: Date = Date()) async throws -> HifzToday? {
        guard let plan = try fetchCurrentPlan()?.toStruct() else { return nil }
        return HifzToday(plan: plan, lessons: try await getAllLessons(), reviews: try await getAllRecentReviews(), now: now)
    }

    /// Every memorized half, from every plan.
    func getAllLessons() async throws -> [HifzLesson] {
        try viewContext.fetch(HifzLessonEntity.fetchRequest()).map { $0.toStruct() }
    }

    /// Every recent review, from every plan, newest first.
    func getAllRecentReviews() async throws -> [HifzReview] {
        try fetchAllRecentReviews().map { $0.toStruct() }
    }

    @discardableResult
    func createPlan(
        title: String,
        startPage: Int,
        endPage: Int,
        halvesPerDay: Int,
        lessonWeekdays: Int16,
        recentReviewCount: Int,
        revisionFrequency: Frequency,
        now: Date = Date()
    ) async throws -> HifzPlan {
        guard try fetchCurrentPlan() == nil else { throw DataStoreError.planAlreadyActive }

        let plan = HifzPlanEntity(context: viewContext)
        plan.id = UUID()
        plan.title = title
        plan.startPage = Int16(startPage)
        plan.endPage = Int16(endPage)
        plan.halvesPerDay = Int16(halvesPerDay)
        plan.lessonWeekdays = lessonWeekdays
        plan.recentReviewCount = Int16(recentReviewCount)
        plan.revisionFrequency = revisionFrequency.rawValue
        plan.isActive = true
        plan.createdAt = now
        plan.updatedAt = now

        try saveOrRollBack()
        return plan.toStruct()
    }

    /// Saves the plan's pace and pause state. Its range can't change once lessons exist.
    func updatePlan(_ plan: HifzPlan, now: Date = Date()) async throws {
        guard let entity = try fetchPlan(id: plan.id) else { throw DataStoreError.planNotFound }

        entity.title = plan.title
        entity.halvesPerDay = Int16(plan.halvesPerDay)
        entity.lessonWeekdays = plan.lessonWeekdays
        entity.recentReviewCount = Int16(plan.recentReviewCount)
        entity.revisionFrequency = plan.revisionFrequency.rawValue
        entity.isActive = plan.isActive
        entity.updatedAt = now

        try saveOrRollBack()
    }

    /// Closes the plan. Everything memorized moves to revision now, including pages only half
    /// learned, so nothing memorized is left without review.
    @discardableResult
    func endPlan(id: UUID, now: Date = Date()) async throws -> MovedToRevision? {
        guard let entity = try fetchPlan(id: id) else { throw DataStoreError.planNotFound }
        let plan = entity.toStruct()

        let unsettled = try fetchLessons(planId: id).filter { $0.graduatedAt == nil }
        unsettled.forEach { $0.graduatedAt = now }
        let pages = plan.pagesInOrder(unsettled.map { Int($0.page) })

        do {
            let moved = try await applyRevisionChanges(pages: pages, plan: plan, now: now)
            entity.isActive = false
            entity.completedAt = now
            entity.updatedAt = now
            try viewContext.save()
            return moved
        } catch {
            viewContext.rollback()
            throw error
        }
    }

    /// Records today's lesson as memorized. Returns the new lessons' ids, for undo.
    @discardableResult
    func memorize(_ halves: [HalfPage], planId: UUID, notes: String?, now: Date = Date()) async throws -> [UUID] {
        guard try fetchPlan(id: planId) != nil else { throw DataStoreError.planNotFound }
        let existing = Set(try fetchLessons(planId: planId).map { HalfPage(page: Int($0.page), half: HalfPage.Half(rawValue: $0.half) ?? .top) })

        var ids: [UUID] = []
        for half in halves where !existing.contains(half) {
            let lesson = HifzLessonEntity(context: viewContext)
            let id = UUID()
            lesson.id = id
            lesson.planId = planId
            lesson.page = Int16(half.page)
            lesson.half = half.half.rawValue
            lesson.memorizedAt = now
            lesson.notes = notes
            ids.append(id)
        }

        do {
            try recalculateStats(now: now)
            try viewContext.save()
        } catch {
            viewContext.rollback()
            throw error
        }
        return ids
    }

    func undoMemorize(lessonIds: [UUID]) async throws {
        let request: NSFetchRequest<HifzLessonEntity> = HifzLessonEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id IN %@", lessonIds)
        try viewContext.fetch(request).forEach(viewContext.delete)

        try recalculateStats()
        try saveOrRollBack()
    }

    /// Logs a recitation of the recent-review block. Returns its id, for undo.
    @discardableResult
    func logRecentReview(
        planId: UUID,
        block: HifzToday.RecentBlock,
        performanceRating: PerformanceRating,
        notes: String?,
        now: Date = Date()
    ) async throws -> UUID {
        guard try fetchPlan(id: planId) != nil else { throw DataStoreError.planNotFound }

        let review = HifzReviewEntity(context: viewContext)
        let id = UUID()
        review.id = id
        review.planId = planId
        review.completedAt = now
        review.performanceRating = performanceRating.rawValue
        review.notes = notes
        review.firstPage = Int16(block.firstPage)
        review.lastPage = Int16(block.lastPage)
        review.halfCount = Int16(block.halfCount)

        do {
            try recalculateStats(now: now)
            try viewContext.save()
        } catch {
            viewContext.rollback()
            throw error
        }
        return id
    }

    /// Edits a past recent review. Anything already moved to revision stays there.
    func updateRecentReview(id: UUID, performanceRating: PerformanceRating, notes: String?) async throws {
        guard let review = try fetchRecentReview(id: id) else { throw DataStoreError.sessionNotFound }

        review.performanceRating = performanceRating.rawValue
        review.notes = notes

        try recalculateStats()
        try saveOrRollBack()
    }

    /// Deletes a recent review, including one just logged. Anything already moved to revision stays there.
    func deleteRecentReview(id: UUID) async throws {
        guard let review = try fetchRecentReview(id: id) else { return }

        viewContext.delete(review)

        try recalculateStats()
        try saveOrRollBack()
    }

    /// Moves halves that have had enough good recent reviews into revision, and finishes the plan
    /// once every half has moved. Reviews logged today only count from tomorrow, so this can run
    /// on every load without an undo ever having to take something back out of revision.
    @discardableResult
    func graduateReadyLessons(now: Date = Date()) async throws -> MovedToRevision? {
        guard let entity = try fetchCurrentPlan(), entity.isActive else { return nil }
        let plan = entity.toStruct()

        let lessonEntities = try fetchLessons(planId: plan.id)
        let lessons = lessonEntities.map { $0.toStruct() }
        let reviews = try fetchAllRecentReviews().map { $0.toStruct() }
        let ready = Set(HifzGraduation.halvesReady(
            lessons: lessons, reviews: reviews, requiredCount: plan.recentReviewCount, now: now
        ).map(\.id))
        guard !ready.isEmpty else { return nil }

        for lesson in lessonEntities where lesson.id.map(ready.contains) == true {
            lesson.graduatedAt = now
        }

        // A page moves once both its halves have.
        let graduated = Set(lessons.filter { $0.graduatedAt != nil || ready.contains($0.id) }.map(\.halfPage))
        let pages = plan.pagesInOrder(lessons.filter { ready.contains($0.id) }.map(\.halfPage.page)).filter {
            graduated.contains(HalfPage(page: $0, half: .top)) && graduated.contains(HalfPage(page: $0, half: .bottom))
        }

        do {
            let moved = try await applyRevisionChanges(pages: pages, plan: plan, now: now)
            if graduated.count >= plan.totalHalves {
                entity.completedAt = now
                entity.updatedAt = now
            }
            try viewContext.save()
            return moved
        } catch {
            viewContext.rollback()
            throw error
        }
    }

    /// Creates or widens the plan's revision schedules for `pages`. Does not save.
    private func applyRevisionChanges(pages: [Int], plan: HifzPlan, now: Date) async throws -> MovedToRevision? {
        guard !pages.isEmpty else { return nil }
        let schedules = try await getAllSchedules()
        let surahs = try await getAllSurahs()
        let changes = HifzGraduation.revisionChanges(pages: pages, planId: plan.id, schedules: schedules, surahs: surahs)

        for change in changes {
            let schedule: ScheduleEntity
            switch change.kind {
            case .create:
                schedule = ScheduleEntity(context: viewContext)
                schedule.id = UUID()
                schedule.surahId = Int16(change.surahId)
                schedule.frequency = plan.revisionFrequency.rawValue
                schedule.hifzPlanId = plan.id
                schedule.isActive = true
                schedule.createdAt = now
                // It was just recited daily in recent review, so the first revision is one interval away.
                schedule.nextDueDate = ReviewEngine.calculateNextDueDate(
                    frequency: plan.revisionFrequency, from: Calendar.current.startOfDay(for: now)
                )
            case .extend(let id):
                guard let existing = try fetchSchedule(id: id) else { continue }
                schedule = existing
            }
            schedule.isFullSurah = change.isFullSurah
            schedule.startPage = Int16(change.pages?.lowerBound ?? 0)
            schedule.endPage = Int16(change.pages?.upperBound ?? 0)
            schedule.updatedAt = now
        }

        let names = changes.compactMap { change in surahs.first { $0.id == change.surahId }?.englishName }
        return names.isEmpty ? nil : MovedToRevision(surahNames: names, frequency: plan.revisionFrequency)
    }

    private func fetchCurrentPlan() throws -> HifzPlanEntity? {
        let request: NSFetchRequest<HifzPlanEntity> = HifzPlanEntity.fetchRequest()
        request.predicate = NSPredicate(format: "completedAt == nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \HifzPlanEntity.createdAt, ascending: false)]
        request.fetchLimit = 1
        return try viewContext.fetch(request).first
    }

    private func fetchPlan(id: UUID) throws -> HifzPlanEntity? {
        let request: NSFetchRequest<HifzPlanEntity> = HifzPlanEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try viewContext.fetch(request).first
    }

    private func fetchLessons(planId: UUID) throws -> [HifzLessonEntity] {
        let request: NSFetchRequest<HifzLessonEntity> = HifzLessonEntity.fetchRequest()
        request.predicate = NSPredicate(format: "planId == %@", planId as CVarArg)
        return try viewContext.fetch(request)
    }

    private func fetchRecentReview(id: UUID) throws -> HifzReviewEntity? {
        let request: NSFetchRequest<HifzReviewEntity> = HifzReviewEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try viewContext.fetch(request).first
    }

    private func fetchAllRecentReviews() throws -> [HifzReviewEntity] {
        let request: NSFetchRequest<HifzReviewEntity> = HifzReviewEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \HifzReviewEntity.completedAt, ascending: false)]
        return try viewContext.fetch(request)
    }

    private func saveOrRollBack() throws {
        do {
            try viewContext.save()
        } catch {
            viewContext.rollback()
            throw error
        }
    }

    // MARK: - Stats Operations

    func getStats() async throws -> UserStatistics {
        // Stats are written when sessions change, but the current streak also depends on today's
        // date, so recompute on read; otherwise missed days would leave an old streak on screen.
        let stats = try recalculateStats()
        if viewContext.hasChanges {
            try viewContext.save()
        }
        return stats.toStruct()
    }

    /// Rebuilds every statistic from the sessions in the context, including unsaved inserts
    /// and deletions. Does not save.
    @discardableResult
    private func recalculateStats(now: Date = Date()) throws -> StatsEntity {
        let request: NSFetchRequest<StatsEntity> = StatsEntity.fetchRequest()
        request.fetchLimit = 1

        let stats: StatsEntity
        if let existing = try viewContext.fetch(request).first {
            stats = existing
        } else {
            stats = StatsEntity(context: viewContext)
            stats.id = UUID()
        }

        // Revision sessions and recent reviews are rated sessions. A memorized lesson has no rating,
        // but it still keeps the streak going.
        let sessions = try fetchAllSessions().filter { !$0.isDeleted }
        let recentReviews = try fetchAllRecentReviews().filter { !$0.isDeleted }
        let lessons = try viewContext.fetch(HifzLessonEntity.fetchRequest()).filter { !$0.isDeleted }
        let ratings = sessions.map(\.performanceRating) + recentReviews.map(\.performanceRating)
        let sessionDates = sessions.compactMap(\.completedAt)
            + recentReviews.compactMap(\.completedAt)
            + lessons.compactMap(\.memorizedAt)

        let totalRating = ratings.reduce(0.0) { sum, rating in
            sum + (PerformanceRating(rawValue: rating ?? "good") ?? .good).numericValue
        }
        let totalSessions = Int16(clamping: ratings.count)
        let averageRating = ratings.isEmpty ? 0.0 : totalRating / Double(ratings.count)
        let lastSessionDate = sessionDates.max()
        let currentStreak = Int16(clamping: ReviewEngine.calculateCurrentStreak(sessionDates: sessionDates, now: now))
        let longestStreak = Int16(clamping: ReviewEngine.calculateLongestStreak(sessionDates: sessionDates))

        // Assign only on change so that reading stats doesn't dirty the context.
        if stats.totalSessions != totalSessions { stats.totalSessions = totalSessions }
        if stats.averageRating != averageRating { stats.averageRating = averageRating }
        if stats.lastSessionDate != lastSessionDate { stats.lastSessionDate = lastSessionDate }
        if stats.currentStreak != currentStreak { stats.currentStreak = currentStreak }
        if stats.longestStreak != longestStreak { stats.longestStreak = longestStreak }
        if stats.hasChanges || stats.updatedAt == nil { stats.updatedAt = now }

        return stats
    }

    // MARK: - Data Management

    func clearAllData() async throws {
        let requests: [NSFetchRequest<NSFetchRequestResult>] = [
            ScheduleEntity.fetchRequest(),
            SessionEntity.fetchRequest(),
            HifzPlanEntity.fetchRequest(),
            HifzLessonEntity.fetchRequest(),
            HifzReviewEntity.fetchRequest(),
        ]

        // Batch deletes bypass the context, so collect the deleted IDs and merge them in;
        // otherwise the context keeps serving the deleted objects.
        var deletedObjectIDs: [NSManagedObjectID] = []
        for request in requests {
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            deleteRequest.resultType = .resultTypeObjectIDs
            let result = try viewContext.execute(deleteRequest) as? NSBatchDeleteResult
            deletedObjectIDs += result?.result as? [NSManagedObjectID] ?? []
        }

        NSManagedObjectContext.mergeChanges(
            fromRemoteContextSave: [NSDeletedObjectsKey: deletedObjectIDs],
            into: [viewContext]
        )

        try recalculateStats()
        try viewContext.save()
    }
}
