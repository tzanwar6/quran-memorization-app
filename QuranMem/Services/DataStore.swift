import CoreData
import Foundation

class DataStore: ObservableObject {
    private let viewContext: NSManagedObjectContext
    
    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = context
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
    
    // MARK: - Schedule Operations
    
    func getAllSchedules() async throws -> [ScheduleWithSurah] {
        let request: NSFetchRequest<ScheduleEntity> = ScheduleEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ScheduleEntity.nextDueDate, ascending: true)]
        request.relationshipKeyPathsForPrefetching = ["surah"]
        
        let schedules = try viewContext.fetch(request)
        var result: [ScheduleWithSurah] = []
        result.reserveCapacity(schedules.count)
        
        // Cache surahs to avoid repeated fetches
        var surahCache: [Int16: SurahEntity] = [:]
        
        for schedule in schedules {
            let surah: SurahEntity
            if let cached = surahCache[schedule.surahId] {
                surah = cached
            } else if let fetched = try await getSurah(id: schedule.surahId) {
                surah = fetched
                surahCache[schedule.surahId] = fetched
            } else {
                continue
            }
            
            result.append(schedule.toScheduleWithSurah(surah: surah))
        }
        
        return result
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
        let request: NSFetchRequest<ScheduleEntity> = ScheduleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        guard let schedule = try viewContext.fetch(request).first else { return }
        
        if let frequency = frequency {
            schedule.frequency = frequency.rawValue
            // Only recalculate next due date if no manual date is provided
            if nextDueDate == nil {
                // Recalculate next due date based on new frequency
                // If the current nextDueDate is in the past, start from today
                // Otherwise, recalculate from the current nextDueDate
                if let currentDueDate = schedule.nextDueDate {
                    let baseDate = currentDueDate < Date() ? Date() : currentDueDate
                    schedule.nextDueDate = ReviewEngine.calculateNextDueDate(frequency: frequency, from: baseDate)
                } else {
                    schedule.nextDueDate = ReviewEngine.calculateNextDueDate(frequency: frequency, from: Date())
                }
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
    
    func deleteSchedule(id: UUID) async throws {
        let request: NSFetchRequest<ScheduleEntity> = ScheduleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        
        if let schedule = try viewContext.fetch(request).first {
            viewContext.delete(schedule)
            try viewContext.save()
        }
    }
    
    // MARK: - Session Operations
    
    func createSession(
        scheduleId: UUID,
        performanceRating: PerformanceRating,
        notes: String? = nil
    ) async throws {
        let session = SessionEntity(context: viewContext)
        session.id = UUID()
        session.scheduleId = scheduleId
        session.performanceRating = performanceRating.rawValue
        session.completedAt = Date()
        session.notes = notes
        
        try viewContext.save()
        
        try await updateScheduleAfterSession(scheduleId: scheduleId, rating: performanceRating)
        try await updateStats()
    }
    
    func getRecentSessions(limit: Int = 20) async throws -> [SessionWithSchedule] {
        let request: NSFetchRequest<SessionEntity> = SessionEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SessionEntity.completedAt, ascending: false)]
        request.fetchLimit = limit
        request.relationshipKeyPathsForPrefetching = ["schedule", "schedule.surah"]
        
        let sessions = try viewContext.fetch(request)
        var result: [SessionWithSchedule] = []
        result.reserveCapacity(sessions.count)
        
        // Cache schedules and surahs to avoid repeated fetches
        var scheduleCache: [UUID: ScheduleEntity] = [:]
        var surahCache: [Int16: SurahEntity] = [:]
        
        for session in sessions {
            guard let sessionScheduleId = session.scheduleId else { continue }
            
            let schedule: ScheduleEntity
            if let cached = scheduleCache[sessionScheduleId] {
                schedule = cached
            } else {
                let scheduleRequest: NSFetchRequest<ScheduleEntity> = ScheduleEntity.fetchRequest()
                scheduleRequest.predicate = NSPredicate(format: "id == %@", sessionScheduleId as CVarArg)
                scheduleRequest.fetchLimit = 1
                
                guard let fetched = try viewContext.fetch(scheduleRequest).first else { continue }
                schedule = fetched
                scheduleCache[sessionScheduleId] = fetched
            }
            
            let surah: SurahEntity
            if let cached = surahCache[schedule.surahId] {
                surah = cached
            } else if let fetched = try await getSurah(id: schedule.surahId) {
                surah = fetched
                surahCache[schedule.surahId] = fetched
            } else {
                continue
            }
            
            result.append(session.toSessionWithSchedule(surah: surah, schedule: schedule))
        }
        
        return result
    }
    
    func getAllSessions() async throws -> [SessionEntity] {
        let request: NSFetchRequest<SessionEntity> = SessionEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SessionEntity.completedAt, ascending: false)]
        return try viewContext.fetch(request)
    }
    
    // MARK: - Stats Operations
    
    func getStats() async throws -> UserStatistics {
        let request: NSFetchRequest<StatsEntity> = StatsEntity.fetchRequest()
        request.fetchLimit = 1
        
        if let stats = try viewContext.fetch(request).first {
            return stats.toStruct()
        }
        
        return UserStatistics(
            currentStreak: 0,
            longestStreak: 0,
            totalSessions: 0,
            averageRating: 0.0,
            lastSessionDate: nil
        )
    }
    
    private func updateStats() async throws {
        let request: NSFetchRequest<StatsEntity> = StatsEntity.fetchRequest()
        request.fetchLimit = 1
        
        guard let stats = try viewContext.fetch(request).first else { return }
        
        let sessions = try await getAllSessions()
        
        stats.totalSessions = Int16(sessions.count)
        
        if !sessions.isEmpty {
            let totalRating = sessions.reduce(0.0) { sum, session in
                let rating = PerformanceRating(rawValue: session.performanceRating ?? "good") ?? .good
                return sum + rating.numericValue
            }
            stats.averageRating = totalRating / Double(sessions.count)
            stats.lastSessionDate = sessions.first?.completedAt
        }
        
        let streak = ReviewEngine.calculateCurrentStreak(sessions: sessions)
        stats.currentStreak = Int16(streak)
        stats.longestStreak = max(stats.longestStreak, Int16(streak))
        stats.updatedAt = Date()
        
        try viewContext.save()
    }
    
    private func updateScheduleAfterSession(scheduleId: UUID, rating: PerformanceRating) async throws {
        let request: NSFetchRequest<ScheduleEntity> = ScheduleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", scheduleId as CVarArg)
        request.fetchLimit = 1
        
        guard let schedule = try viewContext.fetch(request).first else { return }
        
        let frequency = Frequency(rawValue: schedule.frequency ?? "daily") ?? .daily
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currentDueDate = schedule.nextDueDate ?? Date()
        let dueDate = calendar.startOfDay(for: currentDueDate)
        
        // If the task is overdue, calculate next date from the original due date
        // to maintain the schedule. Otherwise calculate from today.
        let baseDate = dueDate < today ? currentDueDate : Date()
        let nextDate = ReviewEngine.calculateNextDueDate(frequency: frequency, from: baseDate)
        
        schedule.nextDueDate = nextDate
        schedule.updatedAt = Date()
        
        try viewContext.save()
    }
    
    // MARK: - Data Management
    
    func clearAllData() async throws {
        let scheduleRequest: NSFetchRequest<NSFetchRequestResult> = ScheduleEntity.fetchRequest()
        let sessionRequest: NSFetchRequest<NSFetchRequestResult> = SessionEntity.fetchRequest()
        
        let deleteSchedules = NSBatchDeleteRequest(fetchRequest: scheduleRequest)
        let deleteSessions = NSBatchDeleteRequest(fetchRequest: sessionRequest)
        
        try viewContext.execute(deleteSchedules)
        try viewContext.execute(deleteSessions)
        
        let statsRequest: NSFetchRequest<StatsEntity> = StatsEntity.fetchRequest()
        if let stats = try viewContext.fetch(statsRequest).first {
            stats.currentStreak = 0
            stats.longestStreak = 0
            stats.totalSessions = 0
            stats.averageRating = 0.0
            stats.lastSessionDate = nil
        }
        
        try viewContext.save()
    }
}
