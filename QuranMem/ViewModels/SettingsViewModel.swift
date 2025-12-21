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
    
    init(dataStore: DataStore = DataStore(), notificationManager: NotificationManager = NotificationManager()) {
        self.dataStore = dataStore
        self.notificationManager = notificationManager
        loadSettings()
    }
    
    func loadSettings() {
        notificationsEnabled = notificationManager.isAuthorized
        
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = 12
        components.minute = 0
        notificationTime = calendar.date(from: components) ?? Date()
    }
    
    func requestNotificationPermission() {
        notificationManager.requestAuthorization()
    }
    
    func updateNotificationTime() async {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: notificationTime)
        
        await notificationManager.scheduleDailyReminder(
            hour: components.hour ?? 12,
            minute: components.minute ?? 0
        )
    }
    
    func toggleNotifications() async {
        if notificationsEnabled {
            await notificationManager.scheduleDailyReminder()
        } else {
            notificationManager.cancelDailyReminder()
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
}
