import Foundation
import CoreData
import Combine

@MainActor
class ProgressViewModel: ObservableObject {
    @Published var sessions: [SessionWithSchedule] = []
    @Published var stats: UserStatistics?
    /// One state per page, for the map.
    @Published private(set) var pageStates: [PageState] = []
    @Published private(set) var surahs: [Surah] = []
    @Published private(set) var planToday: HifzToday?
    @Published private(set) var recentReviews: [HifzReview] = []
    @Published private(set) var lessons: [HifzLesson] = []
    @Published var isLoading = false
    @Published var error: String?

    private let dataStore: DataStore

    init(dataStore: DataStore = DataStore()) {
        self.dataStore = dataStore
    }

    func loadData() async {
        // Prevent multiple simultaneous loads
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            sessions = try await dataStore.getRecentSessions()
            stats = try await dataStore.getStats()
            let schedules = try await dataStore.getAllSchedules()
            let lessons = try await dataStore.getAllLessons()
            let reviews = try await dataStore.getAllRecentReviews()
            let plan = try await dataStore.getCurrentPlan()
            surahs = try await dataStore.getAllSurahs()
            self.recentReviews = reviews
            self.lessons = lessons
            pageStates = PageCoverage.compute(schedules: schedules, lessons: lessons, surahs: surahs)
            planToday = plan.map { HifzToday(plan: $0, lessons: lessons, reviews: reviews) }
        } catch {
            self.error = "Failed to load progress: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func updateSession(id: UUID, performanceRating: PerformanceRating, notes: String?) async {
        do {
            try await dataStore.updateSession(id: id, performanceRating: performanceRating, notes: notes)
            await loadData()
        } catch {
            self.error = "Failed to update session: \(error.localizedDescription)"
        }
    }

    func deleteSession(id: UUID) async {
        do {
            try await dataStore.deleteSession(id: id)
            await loadData()
        } catch {
            self.error = "Failed to delete session: \(error.localizedDescription)"
        }
    }

    func isRecentReview(_ session: SessionWithSchedule) -> Bool {
        recentReviews.contains { $0.id == session.id }
    }

    func updateRecentReview(id: UUID, performanceRating: PerformanceRating, notes: String?) async {
        do {
            try await dataStore.updateRecentReview(id: id, performanceRating: performanceRating, notes: notes)
            await loadData()
        } catch {
            self.error = "Failed to update review: \(error.localizedDescription)"
        }
    }

    func deleteRecentReview(id: UUID) async {
        do {
            try await dataStore.deleteRecentReview(id: id)
            await loadData()
        } catch {
            self.error = "Failed to delete review: \(error.localizedDescription)"
        }
    }

    /// Revision sessions and recent reviews: everything with a rating.
    var ratedSessions: [SessionWithSchedule] {
        sessions + recentReviews.map(\.historySession)
    }

    var historyGroupedByDate: [(Date, [HistoryItem])] {
        let calendar = Calendar.current
        // Halves memorized in one go show as one lesson.
        let lessonGroups = Dictionary(grouping: lessons) { $0.memorizedAt }.values.map { HistoryItem.lesson($0) }
        let items = ratedSessions.map(HistoryItem.rated) + lessonGroups
        let grouped = Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }

        return grouped
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.0 > $1.0 }
    }

    var last7DaysData: [(Date, Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<7).map { daysAgo in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return (today, 0)
            }

            let count = ratedSessions.filter { session in
                calendar.isDate(session.completedAt, inSameDayAs: date)
            }.count

            return (date, count)
        }.reversed()
    }

    var performanceBreakdown: [(PerformanceRating, Int)] {
        let grouped = Dictionary(grouping: ratedSessions) { $0.performanceRating }

        return PerformanceRating.allCases.map { rating in
            (rating, grouped[rating]?.count ?? 0)
        }
    }

    var averageRatingString: String {
        guard let rating = stats?.averageRating else { return "0.0" }
        return String(format: "%.1f", rating)
    }
}

enum HistoryItem: Identifiable {
    /// A revision session or a recent review.
    case rated(SessionWithSchedule)
    /// Halves memorized together as one new lesson.
    case lesson([HifzLesson])

    var id: UUID {
        switch self {
        case .rated(let session): return session.id
        case .lesson(let lessons): return lessons.first?.id ?? UUID()
        }
    }

    var date: Date {
        switch self {
        case .rated(let session): return session.completedAt
        case .lesson(let lessons): return lessons.first?.memorizedAt ?? .distantPast
        }
    }
}

extension HifzReview {
    /// A recent review in the shape History shows sessions in.
    var historySession: SessionWithSchedule {
        SessionWithSchedule(
            id: id,
            scheduleId: planId,
            surahArabicName: "Recent review",
            surahEnglishName: "\(pageRangeDescription) · \(halfCount == 1 ? "1 half page" : "\(halfCount) half pages")",
            performanceRating: performanceRating,
            completedAt: completedAt,
            notes: notes,
            frequency: .daily
        )
    }
}
