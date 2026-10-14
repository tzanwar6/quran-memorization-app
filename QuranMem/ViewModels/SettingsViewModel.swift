import Foundation
import CoreData
import Combine
import FamilyControls

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var notificationTime = Date()
    @Published var notificationsEnabled = false
    @Published var showResetConfirmation = false
    @Published var error: String?
    /// A rule of the permanent lock that stopped something. It's a notice, not a failure.
    @Published var lockNotice: String?
    /// True after the app picker came back with apps unticked that a permanent lock has to keep.
    @Published private(set) var untickedAppsWereKept = false

    private let dataStore: DataStore
    private let notificationManager: NotificationManager
    private let lockManager: AppLockManager

    init(
        dataStore: DataStore = DataStore(),
        notificationManager: NotificationManager = .shared,
        lockManager: AppLockManager? = nil
    ) {
        self.dataStore = dataStore
        self.notificationManager = notificationManager
        // Default arguments are evaluated off the main actor, where `shared` isn't reachable.
        self.lockManager = lockManager ?? .shared
        notificationsEnabled = notificationManager.remindersEnabled && notificationManager.isAuthorized
        notificationTime = Self.date(hour: notificationManager.reminderHour, minute: notificationManager.reminderMinute)
    }

    func loadSettings() async {
        // Permission can change in the Settings app while QuranMem is in the background.
        let authorized = await notificationManager.checkAuthorization()
        notificationsEnabled = notificationManager.remindersEnabled && authorized

        let savedTime = Self.date(hour: notificationManager.reminderHour, minute: notificationManager.reminderMinute)
        if !Calendar.current.isDate(savedTime, equalTo: notificationTime, toGranularity: .minute) {
            notificationTime = savedTime
        }
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        notificationsEnabled = enabled
        let isOn = await notificationManager.setRemindersEnabled(enabled)
        notificationsEnabled = isOn

        if enabled && !isOn {
            error = "Notifications are turned off for QuranMem. You can allow them in the iOS Settings app."
        }
    }

    func updateNotificationTime() async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: notificationTime)
        let hour = components.hour ?? 12
        let minute = components.minute ?? 0

        guard hour != notificationManager.reminderHour || minute != notificationManager.reminderMinute else { return }

        await notificationManager.setReminderTime(hour: hour, minute: minute)
    }

    func setLockEnabled(_ enabled: Bool) async {
        do {
            try await lockManager.setEnabled(enabled)
        } catch FamilyControlsError.authorizationCanceled {
            self.error = "Revision Lock needs Screen Time access to lock apps. Turn it on again and choose Continue when iOS asks."
        } catch let error as LockError {
            lockNotice = error.localizedDescription
        } catch {
            self.error = "Revision Lock couldn’t be turned on. \(error.localizedDescription) Check that Screen Time access is allowed for QuranMem in the iOS Settings app."
        }
    }

    /// Called when the app picker closes. While the settings are fixed the lock keeps the apps it
    /// already has, so anything unticked is put back.
    func appsPicked(_ picked: FamilyActivitySelection) {
        untickedAppsWereKept = lockManager.isFrozen
            && !picked.union(lockManager.selection).hasSameTokens(as: picked)
        lockManager.setSelection(picked)
    }

    func moveChangeWindow(toWeekday weekday: Int, hour: Int, minute: Int) {
        do {
            try lockManager.moveChangeWindow(toWeekday: weekday, hour: hour, minute: minute)
        } catch {
            lockNotice = error.localizedDescription
        }
    }

    func askToResetAllData() {
        if lockManager.isFrozen {
            lockNotice = "Your data can’t be reset while the lock is permanent. You can do it during your weekly change window."
        } else {
            showResetConfirmation = true
        }
    }

    func resetAllData() async {
        do {
            try await dataStore.clearAllData()
            notificationManager.clearBadge()
        } catch {
            self.error = "Failed to reset data: \(error.localizedDescription)"
        }
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private static func date(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
