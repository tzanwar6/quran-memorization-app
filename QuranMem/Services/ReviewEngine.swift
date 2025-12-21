import Foundation
import CoreData

class ReviewEngine {
    static func calculateNextDueDate(frequency: Frequency, from date: Date = Date()) -> Date {
        var components = DateComponents()
        
        if let days = frequency.daysToAdd {
            components.day = days
        } else if let months = frequency.monthsToAdd {
            components.month = months
        }
        
        return Calendar.current.date(byAdding: components, to: date) ?? date
    }
    
    static func calculateCurrentStreak(sessions: [SessionEntity]) -> Int {
        guard !sessions.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        let sortedSessions = sessions.sorted { $0.completedAt ?? Date() > $1.completedAt ?? Date() }
        
        var streak = 0
        let currentDate = calendar.startOfDay(for: Date())
        
        for session in sortedSessions {
            guard let sessionDate = session.completedAt else { continue }
            let sessionDay = calendar.startOfDay(for: sessionDate)
            
            let daysDiff = calendar.dateComponents([.day], from: sessionDay, to: currentDate).day ?? 0
            
            if daysDiff == streak {
                streak += 1
            } else if daysDiff > streak {
                break
            }
        }
        
        return streak
    }
    
    static func calculateLongestStreak(sessions: [SessionEntity]) -> Int {
        guard !sessions.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        let sortedSessions = sessions.sorted { $0.completedAt ?? Date() < $1.completedAt ?? Date() }
        
        var maxStreak = 0
        var currentStreak = 0
        var lastDate: Date?
        
        for session in sortedSessions {
            guard let sessionDate = session.completedAt else { continue }
            let sessionDay = calendar.startOfDay(for: sessionDate)
            
            if let last = lastDate {
                let daysDiff = calendar.dateComponents([.day], from: last, to: sessionDay).day ?? 0
                
                if daysDiff <= 1 {
                    currentStreak += 1
                } else {
                    maxStreak = max(maxStreak, currentStreak)
                    currentStreak = 1
                }
            } else {
                currentStreak = 1
            }
            
            lastDate = sessionDay
        }
        
        return max(maxStreak, currentStreak)
    }
    
    static func getPerformanceColor(for rating: PerformanceRating) -> String {
        return rating.color
    }
    
    static func shouldShowReminder(for schedule: ScheduleWithSurah) -> Bool {
        return schedule.isDueToday && schedule.isActive
    }
}
