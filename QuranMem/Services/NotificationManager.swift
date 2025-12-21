import Foundation
import UserNotifications
import CoreData

class NotificationManager: NSObject, ObservableObject {
    @Published var isAuthorized = false
    private let notificationCenter = UNUserNotificationCenter.current()
    
    override init() {
        super.init()
        notificationCenter.delegate = self
        checkAuthorization()
    }
    
    func requestAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                self.isAuthorized = granted
            }
            
            if let error = error {
                print("Notification authorization error: \(error)")
            }
        }
    }
    
    func checkAuthorization() {
        notificationCenter.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    func scheduleDailyReminder(hour: Int = 12, minute: Int = 0) async {
        notificationCenter.removeAllPendingNotificationRequests()
        
        guard isAuthorized else {
            print("Notifications not authorized")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = "🕌 QuranMem Reminder"
        content.body = "Time to review your Quran memorization!"
        content.sound = .default
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: "daily-reminder", content: content, trigger: trigger)
        
        do {
            try await notificationCenter.add(request)
            print("Daily reminder scheduled for \(hour):\(minute)")
        } catch {
            print("Error scheduling notification: \(error)")
        }
    }
    
    func sendImmediateReminder(taskCount: Int, overdueCount: Int) async {
        guard isAuthorized else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "🕌 QuranMem Reminder"
        
        if overdueCount > 0 {
            content.body = "You have \(overdueCount) overdue task(s) and \(taskCount - overdueCount) task(s) due today."
        } else {
            content.body = "You have \(taskCount) memorization task(s) due today."
        }
        
        content.sound = .default
        content.badge = NSNumber(value: taskCount)
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        do {
            try await notificationCenter.add(request)
        } catch {
            print("Error sending immediate notification: \(error)")
        }
    }
    
    func updateBadgeCount(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count)
    }
    
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
    
    func cancelDailyReminder() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ["daily-reminder"])
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
