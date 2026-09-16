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
    
    init() {
        setupAppearance()
    }
    
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
    
    private func setupAppearance() {
        UINavigationBar.appearance().largeTitleTextAttributes = [
            .foregroundColor: UIColor(Color.islamicGreen)
        ]
        UINavigationBar.appearance().titleTextAttributes = [
            .foregroundColor: UIColor(Color.islamicGreen)
        ]
    }
}

struct ContentView: View {
    @AppStorage("colorScheme") private var colorSchemeString: String = ColorSchemeOption.system.rawValue
    
    private var preferredColorScheme: ColorScheme? {
        switch ColorSchemeOption(rawValue: colorSchemeString) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
            
            SchedulesView()
                .tabItem {
                    Label("Schedules", systemImage: "calendar")
                }
            
            ProgressTabView()
                .tabItem {
                    Label("Progress", systemImage: "chart.bar.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .accentColor(.islamicGreen)
        .preferredColorScheme(preferredColorScheme)
    }
}

extension Color {
    static let islamicGreen = Color(red: 0.02, green: 0.47, blue: 0.34)
    static let islamicDark = Color(red: 0.02, green: 0.37, blue: 0.27)
    static let goldAccent = Color(red: 0.85, green: 0.65, blue: 0.13)
}
