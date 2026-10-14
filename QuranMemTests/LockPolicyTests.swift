import CoreData
import Foundation
import Testing
@testable import QuranMem

private let lockCalendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "UTC")!
    return value
}()
private func lockDate(day: Int = 27, hour: Int, minute: Int = 0) -> Date {
    lockCalendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}
/// Enabled, with one passage due on the 27th unless a test says otherwise.
private func lockState(
    enabled: Bool = true,
    due: [Date] = [lockDate(hour: 0)],
    commitment: LockCommitment? = nil
) -> SharedLockState {
    SharedLockState(isEnabled: enabled, dueDates: due, commitment: commitment)
}
/// Made permanent a week earlier. 27 September 2026 is a Sunday, so by default the change window
/// opens that day at 20:00.
private func permanent(weekday: Int = 1, hour: Int = 20, minute: Int = 0) -> LockCommitment {
    LockCommitment(since: lockDate(day: 20, hour: 9), windowWeekday: weekday, windowHour: hour, windowMinute: minute)
}
private func status(_ state: SharedLockState, at now: Date) -> LockStatus {
    LockPolicy.status(state: state, now: now, calendar: lockCalendar)
}

struct LockPolicyTests {
    @Test func disabledLockNeverShields() {
        #expect(status(lockState(enabled: false), at: lockDate(hour: 12)) == .disabled)
    }

    @Test func locksAllDayWhileAReviewIsDue() {
        #expect(status(lockState(), at: lockDate(hour: 0)) == .locked(remaining: 1))
        #expect(status(lockState(), at: lockDate(hour: 12)) == .locked(remaining: 1))
        #expect(status(lockState(), at: lockDate(hour: 23, minute: 59)) == .locked(remaining: 1))
    }

    @Test func staysLockedPastMidnightUntilTheReviewIsLogged() {
        #expect(status(lockState(), at: lockDate(day: 28, hour: 0, minute: 30)) == .locked(remaining: 1))
    }

    @Test func finishingTodaysReviewsUnlocks() {
        let state = lockState(due: [lockDate(day: 28, hour: 0), lockDate(day: 30, hour: 0)])
        #expect(status(state, at: lockDate(hour: 12)) == .unlockedForToday)
        // Midnight makes tomorrow's passage due.
        #expect(status(state, at: lockDate(day: 28, hour: 0)) == .locked(remaining: 1))
    }

    @Test func quietDayWithNoSchedulesStaysUnlocked() {
        #expect(status(lockState(due: []), at: lockDate(hour: 12)) == .unlockedForToday)
    }

    @Test func overduePassagesCountTowardsTheLock() {
        let state = lockState(due: [lockDate(day: 20, hour: 9), lockDate(hour: 18), lockDate(day: 28, hour: 0)])
        #expect(status(state, at: lockDate(hour: 12)) == .locked(remaining: 2))
    }

    @Test func nextChangeIsMidnight() {
        func next(_ state: SharedLockState, at now: Date) -> Date? {
            LockPolicy.nextChange(state: state, now: now, calendar: lockCalendar)
        }
        #expect(next(lockState(enabled: false), at: lockDate(hour: 12)) == nil)
        #expect(next(lockState(), at: lockDate(hour: 12)) == lockDate(day: 28, hour: 0))
        #expect(next(lockState(due: []), at: lockDate(hour: 12)) == lockDate(day: 28, hour: 0))
    }

    @Test func shouldShieldOnlyWhenLocked() {
        #expect(LockPolicy.shouldShield(state: lockState(), now: lockDate(hour: 12), calendar: lockCalendar))
        #expect(!LockPolicy.shouldShield(state: lockState(due: []), now: lockDate(hour: 12), calendar: lockCalendar))
        #expect(!LockPolicy.shouldShield(state: lockState(enabled: false), now: lockDate(hour: 12), calendar: lockCalendar))
    }
}

struct PermanentLockTests {
    private func isFrozen(_ state: SharedLockState, at now: Date) -> Bool {
        LockPolicy.isFrozen(state: state, now: now, calendar: lockCalendar)
    }

    @Test func settingsAreFixedExceptDuringTheWeeklyHalfHour() {
        let state = lockState(commitment: permanent())
        #expect(isFrozen(state, at: lockDate(hour: 19, minute: 59)))
        #expect(!isFrozen(state, at: lockDate(hour: 20)))
        #expect(!isFrozen(state, at: lockDate(hour: 20, minute: 29)))
        #expect(isFrozen(state, at: lockDate(hour: 20, minute: 30)))
        // The same time on any other day is closed.
        #expect(isFrozen(state, at: lockDate(day: 28, hour: 20, minute: 10)))
        #expect(!isFrozen(state, at: lockDate(day: 20, hour: 20, minute: 10)))
    }

    @Test func nothingIsFixedUntilTheLockIsMadePermanent() {
        #expect(!isFrozen(lockState(), at: lockDate(hour: 12)))
        #expect(!isFrozen(lockState(enabled: false, commitment: permanent()), at: lockDate(hour: 12)))
    }

    @Test func aLateWindowStaysOpenPastMidnight() {
        // Saturday 23:45 to Sunday 00:15.
        let state = lockState(commitment: permanent(weekday: 7, hour: 23, minute: 45))
        #expect(isFrozen(state, at: lockDate(day: 26, hour: 23, minute: 44)))
        #expect(!isFrozen(state, at: lockDate(day: 26, hour: 23, minute: 50)))
        #expect(!isFrozen(state, at: lockDate(hour: 0, minute: 14)))
        #expect(isFrozen(state, at: lockDate(hour: 0, minute: 15)))
    }

    @Test func nextWindowIsLaterTodayOrNextWeek() {
        func next(at now: Date) -> Date? {
            LockPolicy.nextChangeWindow(commitment: permanent(), after: now, calendar: lockCalendar)
        }
        let nextSunday = lockDate(hour: 20).addingTimeInterval(7 * 86_400)
        #expect(next(at: lockDate(hour: 12)) == lockDate(hour: 20))
        #expect(next(at: lockDate(hour: 20, minute: 5)) == nextSunday)
        #expect(next(at: lockDate(day: 28, hour: 9)) == nextSunday)
    }

    @Test func nextChangeIncludesTheChangeWindowsEdges() {
        func next(_ state: SharedLockState, at now: Date) -> Date? {
            LockPolicy.nextChange(state: state, now: now, calendar: lockCalendar)
        }
        let state = lockState(commitment: permanent())
        // At noon the change window opening at 20:00 comes before midnight.
        #expect(next(state, at: lockDate(hour: 12)) == lockDate(hour: 20))
        // While it's open, the next change is it closing.
        #expect(next(state, at: lockDate(hour: 20, minute: 10)) == lockDate(hour: 20, minute: 30))
        // Afterwards midnight comes first again.
        #expect(next(state, at: lockDate(hour: 21)) == lockDate(day: 28, hour: 0))
    }

    @Test func duePassagesAreHeldWhileFixed() {
        func holds(due: Date, active: Bool = true, _ state: SharedLockState, at now: Date = lockDate(hour: 3)) -> Bool {
            LockPolicy.holdsPassage(dueDate: due, isActive: active, state: state, now: now, calendar: lockCalendar)
        }
        let committed = lockState(commitment: permanent())
        // Held from the first minute of the day.
        #expect(holds(due: lockDate(hour: 18), committed))
        #expect(holds(due: lockDate(day: 20, hour: 9), committed))
        #expect(!holds(due: lockDate(day: 28, hour: 0), committed))
        // A paused passage isn't locking anything, so resuming or deleting it is free.
        #expect(!holds(due: lockDate(hour: 18), active: false, committed))
        #expect(!holds(due: lockDate(hour: 18), lockState()))
        // The change window frees schedules too.
        #expect(!holds(due: lockDate(hour: 18), committed, at: lockDate(hour: 20, minute: 10)))
    }
}

@MainActor
struct ScheduleHoldTests {
    private let store = DataStore(context: PersistenceController(inMemory: true).container.viewContext, preferences: { .default })

    private func makeViewModel(held: Bool) async throws -> (SchedulesViewModel, ScheduleWithSurah) {
        try await store.createSchedule(surahId: 1, frequency: .daily, isFullSurah: true)
        let viewModel = SchedulesViewModel(dataStore: store, isHeldByLock: { _ in held })
        await viewModel.loadData()
        return (viewModel, try #require(viewModel.schedules.first))
    }

    @Test func heldPassageCannotBePausedRescheduledOrDeleted() async throws {
        let (viewModel, schedule) = try await makeViewModel(held: true)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

        await viewModel.toggleScheduleActive(id: schedule.id, currentState: true)
        await viewModel.updateSchedule(id: schedule.id, frequency: .monthly, nextDueDate: tomorrow, isActive: nil)
        await viewModel.deleteSchedule(id: schedule.id)

        let saved = try #require(try await store.getAllSchedules().first)
        #expect(saved == schedule)
        #expect(viewModel.lockNotice != nil)
        #expect(viewModel.error == nil)
    }

    @Test func passageThatIsNotHeldCanStillBeChanged() async throws {
        let (viewModel, schedule) = try await makeViewModel(held: false)

        await viewModel.toggleScheduleActive(id: schedule.id, currentState: true)
        #expect(try await store.getAllSchedules().first?.isActive == false)
        #expect(viewModel.lockNotice == nil)

        await viewModel.deleteSchedule(id: schedule.id)
        #expect(try await store.getAllSchedules().isEmpty)
    }
}

struct LockStoreTests {
    private func makeStore() -> (LockStore, UserDefaults, String) {
        let suite = "LockStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (LockStore(defaults: defaults), defaults, suite)
    }

    @Test func startsOff() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(store.state == SharedLockState())
        #expect(!store.state.isEnabled)
    }

    @Test func roundTripsEveryValue() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let due = [lockDate(hour: 0), lockDate(day: 28, hour: 0)]

        store.isEnabled = true
        store.dueDates = due
        #expect(store.state == SharedLockState(isEnabled: true, dueDates: due))
    }

    @Test func roundTripsTheCommitmentAndForgetsItWhenCleared() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(store.commitment == nil)

        let commitment = LockCommitment(since: lockDate(hour: 9), windowWeekday: 6, windowHour: 21, windowMinute: 15)
        store.commitment = commitment
        #expect(store.commitment == commitment)
        #expect(store.state.commitment == commitment)

        store.commitment = nil
        #expect(store.commitment == nil)
    }

    @Test func aCommitmentWithoutAChangeWindowDoesNotCount() {
        let (store, defaults, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        // What an earlier build stored: a start date, and a waiting period instead of a window.
        defaults.set(lockDate(hour: 9), forKey: "revisionLock.permanentSince")
        defaults.set(3, forKey: "revisionLock.turnOffDelayDays")
        #expect(store.commitment == nil)
    }
}
