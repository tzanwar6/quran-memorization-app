import Foundation
import CoreData
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var todaySchedules: [ScheduleWithSurah] = []
    @Published var calendarSchedules: [Date: [ScheduleWithSurah]] = [:]
    @Published var isLoading = false
    @Published var error: String?
    
    private let dataStore: DataStore
    private let notificationManager: NotificationManager
    
    init(dataStore: DataStore = DataStore(), notificationManager: NotificationManager = NotificationManager()) {
        self.dataStore = dataStore
        self.notificationManager = notificationManager
    }
    
    func loadData() async {
        // Prevent multiple simultaneous loads
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        
        do {
            async let todaySchedules = dataStore.getTodaySchedules()
            async let allSchedules = dataStore.getAllSchedules()
            
            self.todaySchedules = try await todaySchedules
            let schedules = try await allSchedules
            
            // Calculate calendar schedules for next 2 weeks
            calendarSchedules = calculateCalendarSchedules(schedules: schedules)
            
            updateBadgeCount()
        } catch {
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
            if currentDate < today {
                currentDate = today
            }
            
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
                
                // Create a copy of the schedule with this due date
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
                    nextDueDate: dateKey,
                    isActive: schedule.isActive
                )
                
                result[dateKey]?.append(scheduleForDate)
                
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
    
    func completeSession(scheduleId: UUID, performanceRating: PerformanceRating, notes: String?) async {
        do {
            try await dataStore.createSession(
                scheduleId: scheduleId,
                performanceRating: performanceRating,
                notes: notes
            )
            await loadData()
        } catch {
            self.error = "Failed to save session: \(error.localizedDescription)"
        }
    }
    
    private func updateBadgeCount() {
        let count = todaySchedules.filter { $0.isDueToday }.count
        Task {
            await notificationManager.updateBadgeCount(count)
        }
    }
}
