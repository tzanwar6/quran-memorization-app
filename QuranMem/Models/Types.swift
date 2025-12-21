import Foundation

enum Frequency: String, CaseIterable, Codable {
    case daily = "daily"
    case weekly = "weekly"
    case biweekly = "biweekly"
    case monthly = "monthly"
    case bimonthly = "bimonthly"
    
    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .biweekly: return "Bi-weekly"
        case .monthly: return "Monthly"
        case .bimonthly: return "Bi-monthly"
        }
    }
    
    var daysToAdd: Int? {
        switch self {
        case .daily: return 1
        case .weekly: return 7
        case .biweekly: return 14
        default: return nil
        }
    }
    
    var monthsToAdd: Int? {
        switch self {
        case .monthly: return 1
        case .bimonthly: return 2
        default: return nil
        }
    }
}

enum PerformanceRating: String, CaseIterable, Codable {
    case perfect = "perfect"
    case veryGood = "very_good"
    case good = "good"
    case poor = "poor"
    case veryPoor = "very_poor"
    
    var displayName: String {
        switch self {
        case .perfect: return "Perfect"
        case .veryGood: return "Very Good"
        case .good: return "Good"
        case .poor: return "Poor"
        case .veryPoor: return "Very Poor"
        }
    }
    
    var description: String {
        switch self {
        case .perfect: return "Flawless recitation"
        case .veryGood: return "Minor mistakes"
        case .good: return "Some hesitation"
        case .poor: return "Multiple mistakes"
        case .veryPoor: return "Struggled significantly"
        }
    }
    
    var stars: Int {
        switch self {
        case .perfect: return 5
        case .veryGood: return 4
        case .good: return 3
        case .poor: return 2
        case .veryPoor: return 1
        }
    }
    
    var numericValue: Double {
        Double(stars)
    }
    
    var color: String {
        switch self {
        case .perfect: return "green"
        case .veryGood: return "blue"
        case .good: return "yellow"
        case .poor: return "orange"
        case .veryPoor: return "red"
        }
    }
}

struct ScheduleWithSurah: Identifiable, Equatable {
    let id: UUID
    let surahId: Int16
    let surahArabicName: String
    let surahEnglishName: String
    let verseCount: Int16
    let frequency: Frequency
    let isFullSurah: Bool
    let startPage: Int16?
    let endPage: Int16?
    let nextDueDate: Date
    let isActive: Bool
    
    var isOverdue: Bool {
        nextDueDate < Calendar.current.startOfDay(for: Date())
    }
    
    var isDueToday: Bool {
        Calendar.current.isDateInToday(nextDueDate) || isOverdue
    }
    
    static func == (lhs: ScheduleWithSurah, rhs: ScheduleWithSurah) -> Bool {
        lhs.id == rhs.id &&
        lhs.surahId == rhs.surahId &&
        lhs.frequency == rhs.frequency &&
        lhs.nextDueDate == rhs.nextDueDate &&
        lhs.isActive == rhs.isActive
    }
}

struct SessionWithSchedule: Identifiable {
    let id: UUID
    let scheduleId: UUID
    let surahArabicName: String
    let surahEnglishName: String
    let performanceRating: PerformanceRating
    let completedAt: Date
    let notes: String?
    let frequency: Frequency
}

struct UserStatistics {
    var currentStreak: Int
    var longestStreak: Int
    var totalSessions: Int
    var averageRating: Double
    var lastSessionDate: Date?
}
