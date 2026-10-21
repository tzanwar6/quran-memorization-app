import Combine
import CoreData
import DeviceActivity
import FamilyControls
import Foundation

enum LockError: LocalizedError {
    case permanent
    case changeWindowClosed

    var errorDescription: String? {
        switch self {
        case .permanent:
            return "The lock is permanent. It can only be turned off during your weekly change window."
        case .changeWindowClosed:
            return "The change window can only be moved while it’s open."
        }
    }
}

/// Runs the Revision Lock from inside the app: mirrors due dates into the App Group for the
/// Screen Time extensions, and applies or lifts the shield as reviews are logged.
@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()

    @Published private(set) var status: LockStatus
    @Published private(set) var selection: FamilyActivitySelection
    /// Set once the lock has been made permanent.
    @Published private(set) var commitment: LockCommitment?
    /// True while a permanent lock's settings are fixed, which is all week except its change window.
    @Published private(set) var isFrozen: Bool

    var isEnabled: Bool { status != .disabled }
    var isPermanent: Bool { commitment != nil }
    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    private let store: LockStore
    private let scheduleProvider: @MainActor () async throws -> [ScheduleWithSurah]
    private var wakeTask: Task<Void, Never>?
    private var hasCheckedMonitoring = false

    private init(
        store: LockStore = LockStore(),
        scheduleProvider: @escaping @MainActor () async throws -> [ScheduleWithSurah] = {
            try await DataStore().getAllSchedules()
        }
    ) {
        LockStore.moveIntoAppGroup()
        self.store = store
        self.scheduleProvider = scheduleProvider
        status = LockPolicy.status(state: store.state)
        selection = store.selection
        commitment = store.isEnabled ? store.commitment : nil
        isFrozen = LockPolicy.isFrozen(state: store.state)

        // Logging the last review should unlock at once, and undoing it should lock again.
        // The manager lives as long as the app, so the observer is never removed.
        _ = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: PersistenceController.shared.container.viewContext,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: - Keeping the shield current

    /// Re-reads the review queue and brings the shield in line with it.
    func refresh() async {
        guard store.isEnabled else {
            status = .disabled
            return
        }
        // Once per launch, so a schedule from an earlier build, or one the system dropped, is replaced.
        if !hasCheckedMonitoring {
            hasCheckedMonitoring = true
            try? startMonitoring()
        }

        do {
            store.dueDates = try await scheduleProvider().filter(\.isActive).map(\.nextDueDate)
        } catch {
            // Keep the last known due dates: unlocking because of a failed read would defeat the lock.
            print("Error reading schedules for the revision lock: \(error)")
        }
        ShieldController.sync(store: store)
        ShieldController.setClockProtection(store.commitment != nil)
        publish()
    }

    private func publish() {
        status = LockPolicy.status(state: store.state)
        commitment = store.commitment
        isFrozen = LockPolicy.isFrozen(state: store.state)
        scheduleWake()
    }

    private func turnOff() {
        store.commitment = nil
        store.isEnabled = false
        DeviceActivityCenter().stopMonitoring([.dailyLock])
        ShieldController.clear()
        ShieldController.setClockProtection(false)
        wakeTask?.cancel()
        status = .disabled
        commitment = nil
        isFrozen = false
    }

    /// Midnight can bring new reviews, and the weekly change window opens and closes by the clock.
    /// Nothing is saved at those moments, so wake up for the next one while the app is open.
    /// When it isn't, the monitor extension locks the apps at midnight.
    private func scheduleWake() {
        wakeTask?.cancel()
        guard let nextChange = LockPolicy.nextChange(state: store.state) else { return }
        wakeTask = Task { [weak self] in
            // One second past the moment, so the clock comparison has definitely flipped.
            do { try await Task.sleep(for: .seconds(max(0, nextChange.timeIntervalSinceNow) + 1)) }
            catch { return }
            await self?.refresh()
        }
    }

    // MARK: - Settings

    /// Turning the lock on asks for Screen Time access the first time. Throws if it isn't granted,
    /// or if the lock is permanent and this isn't its change window.
    func setEnabled(_ enabled: Bool) async throws {
        if enabled {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            try startMonitoring()
            store.isEnabled = true
            await refresh()
        } else {
            guard !LockPolicy.isFrozen(state: store.state) else { throw LockError.permanent }
            turnOff()
        }
    }

    /// While the settings are fixed the lock keeps every app it already has: anything missing
    /// from `selection` is put back.
    func setSelection(_ selection: FamilyActivitySelection) {
        let saved = LockPolicy.isFrozen(state: store.state) ? selection.union(store.selection) : selection
        store.selection = saved
        self.selection = saved
        Task { await refresh() }
    }

    /// Starting an activity that is already monitored replaces its schedule.
    private func startMonitoring() throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        try DeviceActivityCenter().startMonitoring(.dailyLock, during: schedule)
    }

    // MARK: - Permanent lock

    /// From here on the settings are fixed, except for 30 minutes a week starting at this time.
    func makePermanent(windowWeekday: Int, hour: Int, minute: Int) {
        guard store.isEnabled, store.commitment == nil else { return }
        store.commitment = LockCommitment(since: Date(), windowWeekday: windowWeekday, windowHour: hour, windowMinute: minute)
        ShieldController.setClockProtection(true)
        publish()
    }

    /// The change window is a setting like any other, so it can only be moved while it's open.
    func moveChangeWindow(toWeekday weekday: Int, hour: Int, minute: Int) throws {
        guard var commitment = store.commitment else { return }
        guard !LockPolicy.isFrozen(state: store.state) else { throw LockError.changeWindowClosed }
        commitment.windowWeekday = weekday
        commitment.windowHour = hour
        commitment.windowMinute = minute
        store.commitment = commitment
        publish()
    }

    /// Whether the permanent lock stops this passage being paused, deleted or rescheduled.
    func holds(_ schedule: ScheduleWithSurah) -> Bool {
        LockPolicy.holdsPassage(dueDate: schedule.nextDueDate, isActive: schedule.isActive, state: store.state)
    }
}

extension FamilyActivitySelection {
    /// Everything in either selection.
    func union(_ other: FamilyActivitySelection) -> FamilyActivitySelection {
        var merged = self
        merged.applicationTokens.formUnion(other.applicationTokens)
        merged.categoryTokens.formUnion(other.categoryTokens)
        merged.webDomainTokens.formUnion(other.webDomainTokens)
        return merged
    }

    func hasSameTokens(as other: FamilyActivitySelection) -> Bool {
        applicationTokens == other.applicationTokens
            && categoryTokens == other.categoryTokens
            && webDomainTokens == other.webDomainTokens
    }
}
