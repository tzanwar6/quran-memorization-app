import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

// Shared with the Screen Time extensions, so nothing here may depend on app-only code.

extension ManagedSettingsStore.Name {
    static let revision = Self("revision")
    /// Kept apart from the shield's store, which is emptied every time the apps unlock.
    static let commitment = Self("revisionCommitment")
}

extension DeviceActivityName {
    /// Runs all day, every day. Its start at midnight is the monitor extension's cue to check
    /// whether the new day has reviews due.
    static let dailyLock = Self("dailyLock")
}

/// Puts the shield over the chosen apps and takes it off again.
enum ShieldController {
    private static var settings: ManagedSettingsStore { ManagedSettingsStore(named: .revision) }

    static func apply(_ selection: FamilyActivitySelection) {
        let settings = settings
        settings.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        settings.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        settings.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        settings.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
    }

    static func clear() {
        settings.clearAllSettings()
    }

    /// While the lock is permanent the phone's clock has to stay automatic: setting it by hand
    /// would open the weekly change window at will.
    static func setClockProtection(_ isOn: Bool) {
        let settings = ManagedSettingsStore(named: .commitment)
        if isOn {
            settings.dateAndTime.requireAutomaticDateAndTime = true
        } else {
            settings.clearAllSettings()
        }
    }

    /// Brings the shield in line with the stored state.
    static func sync(store: LockStore = LockStore(), now: Date = Date(), calendar: Calendar = .current) {
        if LockPolicy.shouldShield(state: store.state, now: now, calendar: calendar) {
            apply(store.selection)
        } else {
            clear()
        }
    }
}
