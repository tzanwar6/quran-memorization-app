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
    /// Set when the permanent lock stops a change. It's a notice, not a failure.
    @Published var lockNotice: String?
    @Published var showSurahSelection = false
    
    private let dataStore: DataStore
    private let isHeldByLock: @MainActor (ScheduleWithSurah) -> Bool
    
    init(
        dataStore: DataStore = DataStore(),
        isHeldByLock: @escaping @MainActor (ScheduleWithSurah) -> Bool = { AppLockManager.shared.holds($0) }
    ) {
        self.dataStore = dataStore
        self.isHeldByLock = isHeldByLock
    }
    
    /// While a permanent lock's settings are fixed, a passage that's due can't be paused, deleted
    /// or rescheduled: any of those would unlock the apps without the review being done. Says so
    /// and returns true.
    func blocksChange(to schedule: ScheduleWithSurah) -> Bool {
        guard isHeldByLock(schedule) else { return false }
        lockNotice = "\(schedule.surahEnglishName) is due. While the Revision Lock is permanent, a passage that’s due can’t be paused, deleted or rescheduled. Log its review first, or wait for your weekly change window."
        return true
    }
    
    private func blocksChange(toScheduleWithId id: UUID) -> Bool {
        guard let schedule = schedules.first(where: { $0.id == id }) else { return false }
        return blocksChange(to: schedule)
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
        endPage: Int? = nil,
        startsOn: Date = Date()
    ) async throws {
        try await dataStore.createSchedule(
            surahId: Int16(surahId),
            frequency: frequency,
            isFullSurah: isFullSurah,
            startPage: startPage.map { Int16($0) },
            endPage: endPage.map { Int16($0) },
            startsOn: startsOn
        )
        await loadData()
    }
    
    func updateSchedule(id: UUID, frequency: Frequency?, nextDueDate: Date?, isActive: Bool?) async {
        guard !blocksChange(toScheduleWithId: id) else { return }
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
        guard !blocksChange(toScheduleWithId: id) else { return }
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
