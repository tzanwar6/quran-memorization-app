import SwiftUI

enum ColorSchemeOption: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

@main
struct QuranMemApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(notificationManager)
                .task {
                    do {
                        try await DataStore().removeOrphanedSessions()
                    } catch {
                        print("Error removing orphaned sessions: \(error)")
                    }
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    // Reminders are planned from today's date, so rebuild them whenever the app
                    // comes to the foreground. Respects the saved on/off setting and reminder time.
                    guard phase == .active else { return }
                    Task {
                        await notificationManager.refreshDailyReminder()
                    }
                }
        }
    }
    
}

private enum AppTab: Hashable { case home, schedules, progress, settings }

struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    @AppStorage("colorScheme") private var colorSchemeString: String = ColorSchemeOption.system.rawValue
    
    private var preferredColorScheme: ColorScheme? {
        switch ColorSchemeOption(rawValue: colorSchemeString) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(onManageSchedules: { selectedTab = .schedules })
                .tag(AppTab.home)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            SchedulesView()
                .tag(AppTab.schedules)
                .tabItem {
                    Label("Schedules", systemImage: "calendar")
                }
            
            ProgressTabView()
                .tag(AppTab.progress)
                .tabItem {
                    Label("Progress", systemImage: "chart.bar.fill")
                }
            
            SettingsView()
                .tag(AppTab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(.islamicGreen)
        .preferredColorScheme(preferredColorScheme)
    }
}

