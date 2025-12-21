import Foundation
import CoreData
import Combine

@MainActor
class ProgressViewModel: ObservableObject {
    @Published var sessions: [SessionWithSchedule] = []
    @Published var stats: UserStatistics?
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
            async let sessionData = dataStore.getRecentSessions(limit: 100)
            async let statsData = dataStore.getStats()
            
            sessions = try await sessionData
            stats = try await statsData
        } catch {
            self.error = "Failed to load progress: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    var sessionsGroupedByDate: [(Date, [SessionWithSchedule])] {
        let grouped = Dictionary(grouping: sessions) { session in
            Calendar.current.startOfDay(for: session.completedAt)
        }
        
        return grouped.sorted { $0.key > $1.key }
    }
    
    var last7DaysData: [(Date, Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        return (0..<7).map { daysAgo in
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return (today, 0)
            }
            
            let count = sessions.filter { session in
                calendar.isDate(session.completedAt, inSameDayAs: date)
            }.count
            
            return (date, count)
        }.reversed()
    }
    
    var performanceBreakdown: [(PerformanceRating, Int)] {
        let grouped = Dictionary(grouping: sessions) { $0.performanceRating }
        
        return PerformanceRating.allCases.map { rating in
            (rating, grouped[rating]?.count ?? 0)
        }
    }
    
    var averageRatingString: String {
        guard let rating = stats?.averageRating else { return "0.0" }
        return String(format: "%.1f", rating)
    }
}
