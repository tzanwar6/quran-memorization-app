import CoreData
import Foundation

enum DataStoreError: LocalizedError {
    case scheduleNotFound
    case sessionNotFound

    var errorDescription: String? {
        switch self {
        case .scheduleNotFound: return "The schedule no longer exists."
        case .sessionNotFound: return "The session no longer exists."
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

        return schedules.compactMap { schedule in
            surahs[schedule.surahId].map { schedule.toScheduleWithSurah(surah: $0) }
        }
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
        endPage: Int16? = nil
    ) async throws {
        let schedule = ScheduleEntity(context: viewContext)
        schedule.id = UUID()
        schedule.surahId = surahId
        schedule.frequency = frequency.rawValue
        schedule.isFullSurah = isFullSurah
        schedule.startPage = startPage ?? 0
        schedule.endPage = endPage ?? 0
        schedule.nextDueDate = Date()
        schedule.isActive = true
        schedule.createdAt = Date()
        schedule.updatedAt = Date()

        try viewContext.save()
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
            surahEnglishName: try await getSurah(id: schedule.surahId)?.englishName ?? "",
            previousDueDate: previousDueDate,
            nextDueDate: nextDueDate
        )
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

        let sessions = try fetchAllSessions().filter { !$0.isDeleted }
        let sessionDates = sessions.compactMap(\.completedAt)

        let totalRating = sessions.reduce(0.0) { sum, session in
            let rating = PerformanceRating(rawValue: session.performanceRating ?? "good") ?? .good
            return sum + rating.numericValue
        }
        let totalSessions = Int16(clamping: sessions.count)
        let averageRating = sessions.isEmpty ? 0.0 : totalRating / Double(sessions.count)
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
        let scheduleRequest: NSFetchRequest<NSFetchRequestResult> = ScheduleEntity.fetchRequest()
        let sessionRequest: NSFetchRequest<NSFetchRequestResult> = SessionEntity.fetchRequest()

        // Batch deletes bypass the context, so collect the deleted IDs and merge them in;
        // otherwise the context keeps serving the deleted objects.
        var deletedObjectIDs: [NSManagedObjectID] = []
        for request in [scheduleRequest, sessionRequest] {
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
