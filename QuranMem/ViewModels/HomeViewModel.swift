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
    /// The most recently completed session, while it can still be undone.
    @Published var lastCompleted: CompletedSession?
    
    var dailySummary: DailyReviewSummary {
        DailyReviewSummary(schedules: allSchedules, sessions: sessions)
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
    
    init(dataStore: DataStore = DataStore(), notificationManager: NotificationManager = .shared) {
        self.dataStore = dataStore
        self.notificationManager = notificationManager
    }
    
    func loadData() async {
        // Prevent multiple simultaneous loads
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        
        do {
            let schedules = try await dataStore.getAllSchedules()
            let sessions = try await dataStore.getRecentSessions()
            let surahs = try await dataStore.getAllSurahs()
            // Publish one complete snapshot only after every fetch succeeds.
            self.allSchedules = schedules
            self.sessions = sessions
            self.surahs = surahs
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
                    isActive: schedule.isActive
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
        lastCompleted = completed
        await loadData()
        return completed
    }

    func createSchedule(surahId: Int, frequency: Frequency, isFullSurah: Bool, startPage: Int?, endPage: Int?) async throws {
        try await dataStore.createSchedule(
            surahId: Int16(surahId), frequency: frequency, isFullSurah: isFullSurah,
            startPage: startPage.map { Int16($0) }, endPage: endPage.map { Int16($0) }
        )
        await loadData()
    }

    func undoLastSession() async {
        guard let completed = lastCompleted else { return }
        do {
            try await dataStore.undoSession(completed)
            lastCompleted = nil
            await loadData()
        } catch {
            self.error = "Failed to undo session: \(error.localizedDescription)"
        }
    }
    
    func dismissUndo(for completed: CompletedSession) {
        if lastCompleted == completed {
            lastCompleted = nil
        }
    }
    
    private func updateBadgeCount() {
        let count = todaySchedules.filter { $0.isDueToday }.count
        notificationManager.updateBadgeCount(count)
    }
}
