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
    @StateObject private var notificationManager = NotificationManager()
    
    init() {
        setupAppearance()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(notificationManager)
                .onAppear {
                    notificationManager.requestAuthorization()
                    Task {
                        await notificationManager.scheduleDailyReminder()
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
            
            ProgressView()
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
