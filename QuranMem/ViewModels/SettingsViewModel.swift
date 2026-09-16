import Foundation
import CoreData
import Combine

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var notificationTime = Date()
    @Published var notificationsEnabled = false
    @Published var showResetConfirmation = false
    @Published var error: String?

    private let dataStore: DataStore
    private let notificationManager: NotificationManager

    init(dataStore: DataStore = DataStore(), notificationManager: NotificationManager = .shared) {
        self.dataStore = dataStore
        self.notificationManager = notificationManager
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
