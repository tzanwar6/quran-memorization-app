import Foundation
import UserNotifications
import CoreData

class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    static let remindersEnabledKey = "remindersEnabled"
    static let reminderHourKey = "reminderHour"
    static let reminderMinuteKey = "reminderMinute"
    /// Earlier versions used this exact identifier for one repeating reminder; per-day reminders
    /// append the date, so matching the prefix cleans up both.
    private static let reminderIdPrefix = "daily-reminder"

    @Published private(set) var isAuthorized = false
    private let notificationCenter = UNUserNotificationCenter.current()
    private let defaults: UserDefaults
    private let scheduleProvider: @MainActor () async throws -> [ScheduleWithSurah]
    private var refreshTask: Task<Void, Never>?
    private var saveObserver: NSObjectProtocol?

    private init(
        defaults: UserDefaults = .standard,
        scheduleProvider: @escaping @MainActor () async throws -> [ScheduleWithSurah] = {
            try await DataStore().getAllSchedules()
        }
    ) {
        self.defaults = defaults
        self.scheduleProvider = scheduleProvider
        defaults.register(defaults: [
            Self.remindersEnabledKey: true,
            Self.reminderHourKey: 12,
            Self.reminderMinuteKey: 0
        ])
        super.init()
        notificationCenter.delegate = self

        // Reminders list what's due, so rebuild them whenever schedules or sessions are saved.
        saveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: PersistenceController.shared.container.viewContext,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleRefresh()
        }

        Task { await checkAuthorization() }
    }

    deinit {
        if let saveObserver = saveObserver {
            NotificationCenter.default.removeObserver(saveObserver)
        }
    }

    // MARK: - Preferences

    var remindersEnabled: Bool {
        defaults.bool(forKey: Self.remindersEnabledKey)
    }

    var reminderHour: Int {
        defaults.integer(forKey: Self.reminderHourKey)
    }

    var reminderMinute: Int {
        defaults.integer(forKey: Self.reminderMinuteKey)
    }

    // MARK: - Authorization

    /// Prompts on first use; afterwards returns the user's existing decision without prompting.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            _ = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("Notification authorization error: \(error)")
        }
        return await checkAuthorization()
    }

    @discardableResult
    func checkAuthorization() async -> Bool {
        let settings = await notificationCenter.notificationSettings()
        let authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        await MainActor.run {
            self.isAuthorized = authorized
        }
        return authorized
    }

    // MARK: - Daily Reminders

    /// Brings the scheduled reminders in line with the saved preferences and current schedules.
    func refreshDailyReminder() async {
        guard remindersEnabled, await requestAuthorization() else {
            await cancelDailyReminders()
            return
        }

        do {
            let schedules = try await scheduleProvider()
            let plan = ReminderPlanner.plan(schedules: schedules, hour: reminderHour, minute: reminderMinute)
            await replaceReminders(with: plan)
        } catch {
            print("Error planning reminders: \(error)")
        }
    }

    /// Saves the preference and returns whether reminders are actually on afterwards
    /// (false if the user asked to enable them but notification permission is denied).
    func setRemindersEnabled(_ enabled: Bool) async -> Bool {
        defaults.set(enabled, forKey: Self.remindersEnabledKey)
        await refreshDailyReminder()
        return enabled && isAuthorized
    }

    func setReminderTime(hour: Int, minute: Int) async {
        defaults.set(hour, forKey: Self.reminderHourKey)
        defaults.set(minute, forKey: Self.reminderMinuteKey)
        await refreshDailyReminder()
    }

    /// Coalesces bursts of saves (e.g. completing a session saves more than once) into one refresh.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshDailyReminder()
        }
    }

    private func replaceReminders(with plan: [PlannedReminder]) async {
        let calendar = Calendar.current
        let requests = plan.map { reminder -> UNNotificationRequest in
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.badge = NSNumber(value: reminder.badge)

            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let day = calendar.dateComponents([.year, .month, .day], from: reminder.fireDate)
            let identifier = String(format: "%@-%04d-%02d-%02d", Self.reminderIdPrefix, day.year ?? 0, day.month ?? 0, day.day ?? 0)

            return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        }

        // Remove only reminders that aren't in the new plan; re-adding an identifier replaces it.
        // This keeps overlapping refreshes from deleting each other's reminders.
        let plannedIds = Set(requests.map(\.identifier))
        let staleIds = await pendingReminderIds().filter { !plannedIds.contains($0) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: staleIds)

        for request in requests {
            do {
                try await notificationCenter.add(request)
            } catch {
                print("Error scheduling reminder: \(error)")
            }
        }
    }

    private func pendingReminderIds() async -> [String] {
        await notificationCenter.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.reminderIdPrefix) }
    }

    func cancelDailyReminders() async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: await pendingReminderIds())
    }

    // MARK: - Badge

    func updateBadgeCount(_ count: Int) {
        notificationCenter.setBadgeCount(count)
    }

    func clearBadge() {
        notificationCenter.setBadgeCount(0)
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
