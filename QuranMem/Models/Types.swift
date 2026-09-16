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
    
    /// Whether this rating means the passage needs to come back sooner than planned.
    var needsEarlierReview: Bool {
        self == .poor || self == .veryPoor
    }
}

enum OverduePolicy: String, CaseIterable, Codable {
    /// Skip the missed occurrences and stay on the original rhythm (e.g. same weekday).
    case keepRhythm = "keep_rhythm"
    /// Count the next interval from the day the overdue review is completed.
    case restartFromCompletion = "restart_from_completion"
    
    var displayName: String {
        switch self {
        case .keepRhythm: return "Keep Rhythm"
        case .restartFromCompletion: return "Restart From Today"
        }
    }
    
    var description: String {
        switch self {
        case .keepRhythm: return "Overdue reviews move to their next regular date, e.g. the same weekday."
        case .restartFromCompletion: return "Overdue reviews count the next interval from the day you complete them."
        }
    }
}

struct SchedulingPreferences: Equatable {
    static let adjustForRatingKey = "adjustScheduleForRating"
    static let overduePolicyKey = "overduePolicy"
    
    var adjustForRating: Bool
    var overduePolicy: OverduePolicy
    
    static let `default` = SchedulingPreferences(adjustForRating: true, overduePolicy: .keepRhythm)
    
    static func load(from defaults: UserDefaults = .standard) -> SchedulingPreferences {
        let adjustForRating = defaults.object(forKey: adjustForRatingKey) as? Bool ?? Self.default.adjustForRating
        let overduePolicy = defaults.string(forKey: overduePolicyKey).flatMap(OverduePolicy.init(rawValue:))
            ?? Self.default.overduePolicy
        return SchedulingPreferences(adjustForRating: adjustForRating, overduePolicy: overduePolicy)
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

struct SessionWithSchedule: Identifiable, Equatable {
    let id: UUID
    let scheduleId: UUID
    let surahArabicName: String
    let surahEnglishName: String
    let performanceRating: PerformanceRating
    let completedAt: Date
    let notes: String?
    let frequency: Frequency
}

/// What's needed to undo a just-completed session, including the schedule's due date before it.
struct CompletedSession: Equatable {
    let sessionId: UUID
    let scheduleId: UUID
    let surahEnglishName: String
    let previousDueDate: Date
    let nextDueDate: Date
}

struct UserStatistics {
    var currentStreak: Int
    var longestStreak: Int
    var totalSessions: Int
    var averageRating: Double
    var lastSessionDate: Date?
}
