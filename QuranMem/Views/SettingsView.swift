import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @AppStorage("colorScheme") private var colorSchemeString: String = ColorSchemeOption.system.rawValue
    @AppStorage(SchedulingPreferences.adjustForRatingKey) private var adjustForRating = SchedulingPreferences.default.adjustForRating
    @AppStorage(SchedulingPreferences.overduePolicyKey) private var overduePolicyRaw = SchedulingPreferences.default.overduePolicy.rawValue
    
    private var overduePolicy: OverduePolicy {
        OverduePolicy(rawValue: overduePolicyRaw) ?? SchedulingPreferences.default.overduePolicy
    }
    
    var body: some View {
        NavigationView {
            List {
                appearanceSection
                notificationsSection
                schedulingSection
                dataManagementSection
                aboutSection
            }
            .navigationTitle("Settings")
        }
        .task {
            await viewModel.loadSettings()
        }
        .errorAlert($viewModel.error)
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
                    Task {
                        await viewModel.setNotificationsEnabled(newValue)
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
            Text("Get a reminder listing the reviews due that day. Days with nothing due are skipped.")
        }
    }
    
    private var schedulingSection: some View {
        Section {
            Toggle("Adjust for Performance", isOn: $adjustForRating)
                .tint(.islamicGreen)
            
            Picker("Overdue Reviews", selection: $overduePolicyRaw) {
                ForEach(OverduePolicy.allCases, id: \.self) { policy in
                    Text(policy.displayName).tag(policy.rawValue)
                }
            }
        } header: {
            Text("Scheduling")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(adjustForRating
                     ? "A Poor rating brings a review back after about half its usual interval, and Very Poor makes it due tomorrow."
                     : "Reviews always follow their frequency, whatever the rating.")
                Text(overduePolicy.description)
            }
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
