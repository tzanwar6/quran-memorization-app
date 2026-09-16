import Foundation
import CoreData
import Combine

@MainActor
class SchedulesViewModel: ObservableObject {
    @Published var schedules: [ScheduleWithSurah] = []
    @Published var surahs: [Surah] = []
    @Published var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published var error: String?
    @Published var showSurahSelection = false
    
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
            async let scheduleData = dataStore.getAllSchedules()
            async let surahData = dataStore.getAllSurahs()
            
            schedules = try await scheduleData
            surahs = try await surahData
        } catch {
            self.error = "Failed to load schedules: \(error.localizedDescription)"
        }
        
        isLoading = false
        hasLoaded = true
    }
    
    func createSchedule(
        surahId: Int,
        frequency: Frequency,
        isFullSurah: Bool,
        startPage: Int? = nil,
        endPage: Int? = nil
    ) async {
        do {
            try await dataStore.createSchedule(
                surahId: Int16(surahId),
                frequency: frequency,
                isFullSurah: isFullSurah,
                startPage: startPage.map { Int16($0) },
                endPage: endPage.map { Int16($0) }
            )
            await loadData()
        } catch {
            self.error = "Failed to create schedule: \(error.localizedDescription)"
        }
    }
    
    func updateSchedule(id: UUID, frequency: Frequency?, nextDueDate: Date?, isActive: Bool?) async {
        do {
            try await dataStore.updateSchedule(
                id: id,
                frequency: frequency,
                nextDueDate: nextDueDate,
                isActive: isActive
            )
            await loadData()
        } catch {
            self.error = "Failed to update schedule: \(error.localizedDescription)"
        }
    }
    
    func deleteSchedule(id: UUID) async {
        do {
            try await dataStore.deleteSchedule(id: id)
            await loadData()
        } catch {
            self.error = "Failed to delete schedule: \(error.localizedDescription)"
        }
    }
    
    func sessionCount(scheduleId: UUID) -> Int {
        (try? dataStore.sessionCount(scheduleId: scheduleId)) ?? 0
    }
    
    func toggleScheduleActive(id: UUID, currentState: Bool) async {
        await updateSchedule(id: id, frequency: nil, nextDueDate: nil, isActive: !currentState)
    }
    
    func updateScheduleFrequency(id: UUID, frequency: Frequency) async {
        await updateSchedule(id: id, frequency: frequency, nextDueDate: nil, isActive: nil)
    }
}
