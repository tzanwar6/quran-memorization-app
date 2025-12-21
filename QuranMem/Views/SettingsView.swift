import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var notificationManager: NotificationManager
    @AppStorage("colorScheme") private var colorSchemeString: String = ColorSchemeOption.system.rawValue
    
    private var colorSchemeOption: ColorSchemeOption {
        ColorSchemeOption(rawValue: colorSchemeString) ?? .system
    }
    
    var body: some View {
        NavigationView {
            List {
                appearanceSection
                notificationsSection
                dataManagementSection
                aboutSection
        }
        .navigationTitle("Settings")
        }
    }
    
    private var preferredColorScheme: ColorScheme? {
        switch colorSchemeOption {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $colorSchemeString) {
                ForEach(ColorSchemeOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Choose your preferred color scheme")
        }
    }
    
    private var notificationsSection: some View {
        Section {
            Toggle("Daily Reminders", isOn: Binding(
                get: { viewModel.notificationsEnabled },
                set: { newValue in
                    viewModel.notificationsEnabled = newValue
                    if newValue && !notificationManager.isAuthorized {
                        viewModel.requestNotificationPermission()
                    }
                    Task {
                        await viewModel.toggleNotifications()
                    }
                }
            ))
            
            if viewModel.notificationsEnabled {
                DatePicker(
                    "Reminder Time",
                    selection: $viewModel.notificationTime,
                    displayedComponents: .hourAndMinute
                )
                .onChange(of: viewModel.notificationTime) {
                    Task {
                        await viewModel.updateNotificationTime()
                    }
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Receive daily reminders to review your Quran memorization")
        }
    }
    
    private var dataManagementSection: some View {
        Section {
            Button(role: .destructive) {
                viewModel.showResetConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Reset All Data")
                }
            }
        } header: {
            Text("Data Management")
        } footer: {
            Text("This will delete all schedules, sessions, and statistics. This action cannot be undone.")
        }
        .alert("Reset All Data", isPresented: $viewModel.showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                Task {
                    await viewModel.resetAllData()
                }
            }
        } message: {
            Text("Are you sure you want to delete all your data? This action cannot be undone.")
        }
    }
    
    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(viewModel.appVersion)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Build")
                Spacer()
                Text(viewModel.buildNumber)
                    .foregroundColor(.secondary)
            }
            
            Link(destination: URL(string: "https://quranmem.app")!) {
                HStack {
                    Text("Website")
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.caption)
                        .foregroundColor(.islamicGreen)
                }
            }
        } header: {
            Text("About")
        } footer: {
            VStack(alignment: .center, spacing: 8) {
                Text("QuranMem")
                    .font(.headline)
                
                Text("May Allah make your memorization journey easy")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("بارك الله فيك")
                    .font(.caption)
                    .foregroundColor(.islamicGreen)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)
        }
    }
}
