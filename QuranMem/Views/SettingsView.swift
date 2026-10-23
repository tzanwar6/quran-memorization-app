import FamilyControls
import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject private var lockManager = AppLockManager.shared
    @State private var showAppPicker = false
    @State private var draftSelection = FamilyActivitySelection()
    @State private var changeWindowSheet: ChangeWindowSheet.Purpose?
    @AppStorage("colorScheme") private var colorSchemeString: String = ColorSchemeOption.system.rawValue
    @AppStorage(SchedulingPreferences.adjustForRatingKey) private var adjustForRating = SchedulingPreferences.default.adjustForRating
    @AppStorage(SchedulingPreferences.overduePolicyKey) private var overduePolicyRaw = SchedulingPreferences.default.overduePolicy.rawValue
    
    private var overduePolicy: OverduePolicy {
        OverduePolicy(rawValue: overduePolicyRaw) ?? SchedulingPreferences.default.overduePolicy
    }
    
    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                notificationsSection
                revisionLockSection
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
            .tint(.islamicGreen)
            
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
    
    private var revisionLockSection: some View {
        Section {
            Toggle("Lock Apps Until Reviewed", isOn: Binding(
                get: { lockManager.isEnabled },
                set: { newValue in
                    Task {
                        await viewModel.setLockEnabled(newValue)
                    }
                }
            ))
            .tint(.islamicGreen)
            .disabled(lockManager.isFrozen)
            
            if lockManager.isEnabled {
                appsToLockRow

                Toggle("Include Memorization", isOn: Binding(
                    get: { lockManager.includesMemorization },
                    set: { newValue in
                        Task { await viewModel.setLockIncludesMemorization(newValue) }
                    }
                ))
                .tint(.islamicGreen)
                .disabled(lockManager.isFrozen && lockManager.includesMemorization)
                
                if viewModel.untickedAppsWereKept {
                    Text("The apps you unticked were kept. Apps can only be removed during your weekly change window.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                RevisionLockStatusRow(status: lockManager.status, hasSelection: lockManager.hasSelection)
                
                permanenceRows
            }
        } header: {
            Text("Revision Lock")
        } footer: {
            Text(lockFooter)
        }
        .errorAlert($viewModel.lockNotice, title: "Revision Lock")
        .sheet(item: $changeWindowSheet) { purpose in
            ChangeWindowSheet(purpose: purpose, commitment: lockManager.commitment) { weekday, hour, minute in
                switch purpose {
                case .makePermanent:
                    lockManager.makePermanent(windowWeekday: weekday, hour: hour, minute: minute)
                case .moveWindow:
                    viewModel.moveChangeWindow(toWeekday: weekday, hour: hour, minute: minute)
                }
            }
        }
    }
    
    private var lockFooter: String {
        if lockManager.isFrozen {
            return "The lock is permanent. You can add apps, but nothing can be loosened until your weekly change window."
        }
        if lockManager.isPermanent {
            return "Your change window is open. Anything here can be changed, and the lock can be turned off, until it closes."
        }
        if lockManager.isEnabled && lockManager.includesMemorization {
            return "Locks the apps you choose until today’s reviews, new lesson and recent review are logged. Days with nothing due stay unlocked."
        }
        return "Locks the apps you choose until today’s reviews are logged. Days with nothing due stay unlocked."
    }
    
    private var appsToLockRow: some View {
        // Opens the picker straight away. Asking for confirmation in a dialog first left the picker
        // unable to open: a sheet can't be presented while the dialog is still closing.
        Button {
            draftSelection = lockManager.selection
            showAppPicker = true
        } label: {
            LabeledContent("Apps to Lock", value: lockSelectionSummary)
        }
        .foregroundStyle(.primary)
        // The picker edits a draft, so the rules are applied once, when it closes.
        .familyActivityPicker(isPresented: $showAppPicker, selection: $draftSelection)
        .onChange(of: showAppPicker) { _, isShowing in
            if !isShowing {
                viewModel.appsPicked(draftSelection)
            }
        }
    }
    
    @ViewBuilder
    private var permanenceRows: some View {
        if let commitment = lockManager.commitment {
            if let window = LockPolicy.openChangeWindow(commitment: commitment) {
                SettingsDetailRow(
                    symbol: "clock",
                    tint: .islamicGreen,
                    title: "Change Window Open",
                    detail: "Until \(window.end.formatted(date: .omitted, time: .shortened)) you can change these settings or turn the lock off."
                )
                Button("Move the Weekly Window…") {
                    changeWindowSheet = .moveWindow
                }
            } else {
                SettingsDetailRow(
                    symbol: "lock.shield",
                    title: "Permanent",
                    detail: "Settings can be changed for 30 minutes from \(Self.nextWindowText(for: commitment))."
                )
            }
        } else {
            Button("Make It Permanent…") {
                changeWindowSheet = .makePermanent
            }
            .disabled(!lockManager.hasSelection)
        }
    }
    
    private static func nextWindowText(for commitment: LockCommitment) -> String {
        guard let next = LockPolicy.nextChangeWindow(commitment: commitment) else { return "your weekly change window" }
        return next.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
    }
    
    private var lockSelectionSummary: String {
        let selection = lockManager.selection
        let parts = [
            (selection.applicationTokens.count, "app", "apps"),
            (selection.categoryTokens.count, "category", "categories"),
            (selection.webDomainTokens.count, "website", "websites")
        ]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.0 == 1 ? $0.1 : $0.2)" }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
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
                viewModel.askToResetAllData()
            } label: {
                // The destructive role reds the title but not the glyph, which
                // otherwise picks up the app's green tint from the tab view.
                Label {
                    Text("Reset All Data")
                } icon: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Data Management")
        } footer: {
            Text("This will delete all schedules, memorization plans, sessions, and statistics. This action cannot be undone.")
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
            LabeledContent("Version", value: viewModel.appVersion)
            LabeledContent("Build", value: viewModel.buildNumber)
        } header: {
            Text("About")
        } footer: {
            VStack(alignment: .center, spacing: 8) {
                Text("QuranMem")
                    .font(.headline)
                
                Text("May Allah make your memorization journey easy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Text("بارك الله فيك")
                    .font(.caption)
                    .foregroundStyle(Color.islamicGreen)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)
        }
    }
}

/// Says whether the chosen apps are locked right now, and why or why not.
struct RevisionLockStatusRow: View {
    let status: LockStatus
    let hasSelection: Bool

    var body: some View {
        SettingsDetailRow(
            symbol: isLocked ? "lock.fill" : "lock.open",
            tint: isLocked ? Color.islamicGreen : .secondary,
            title: title,
            detail: detail
        )
    }

    private var isLocked: Bool {
        if case .locked = status { return hasSelection }
        return false
    }

    private var title: String {
        guard hasSelection else { return "No Apps Chosen" }
        switch status {
        case .disabled: return "Off"
        case .unlockedForToday: return "Unlocked for Today"
        case .locked: return "Locked Now"
        }
    }

    private var detail: String {
        guard hasSelection else { return "Choose the apps to lock, and they’ll lock when a review is due." }
        switch status {
        case .disabled:
            return "Apps are never locked."
        case .unlockedForToday:
            return "Nothing is left to log today, so apps stay open."
        case .locked(let remaining):
            return "\(remaining) left to log today. Apps unlock when \(remaining == 1 ? "it’s" : "they’re") logged."
        }
    }
}

/// A read-only row: a state, and a line underneath saying what it means.
struct SettingsDetailRow: View {
    let symbol: String
    var tint: Color = .secondary
    let title: String
    let detail: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Picks the weekly half hour when a permanent lock's settings can be changed.
struct ChangeWindowSheet: View {
    enum Purpose: String, Identifiable {
        case makePermanent, moveWindow
        var id: String { rawValue }
    }

    let purpose: Purpose
    let onConfirm: (_ weekday: Int, _ hour: Int, _ minute: Int) -> Void
    @State private var weekday: Int
    @State private var time: Date
    @Environment(\.dismiss) private var dismiss

    /// Starts from the current window when there is one, otherwise from today's weekday at 8 PM.
    init(purpose: Purpose, commitment: LockCommitment?, onConfirm: @escaping (Int, Int, Int) -> Void) {
        self.purpose = purpose
        self.onConfirm = onConfirm
        let calendar = Calendar.current
        _weekday = State(initialValue: commitment?.windowWeekday ?? calendar.component(.weekday, from: Date()))
        _time = State(initialValue: calendar.date(
            bySettingHour: commitment?.windowHour ?? 20,
            minute: commitment?.windowMinute ?? 0,
            second: 0,
            of: Date()
        ) ?? Date())
    }

    /// Weekdays in the region's order, as `Calendar` weekday numbers (1 is Sunday).
    private var weekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Day", selection: $weekday) {
                        ForEach(weekdays, id: \.self) { day in
                            Text(Calendar.current.weekdaySymbols[day - 1]).tag(day)
                        }
                    }
                    DatePicker("Opens At", selection: $time, displayedComponents: .hourAndMinute)
                } header: {
                    Text("Weekly Change Window")
                } footer: {
                    Text("For 30 minutes from this time each week, you can change the lock’s settings or turn it off.")
                }

                if purpose == .makePermanent {
                    Section {
                        Label("The lock can’t be turned off", systemImage: "lock.fill")
                        Label("Apps can be added but not removed", systemImage: "plus.app")
                        Label("A passage that’s due can’t be paused, deleted or rescheduled", systemImage: "calendar.badge.exclamationmark")
                        Label("The phone’s date and time stay automatic", systemImage: "clock.badge.checkmark")
                    } header: {
                        Text("The Rest of the Week")
                    }
                }
            }
            .navigationTitle(purpose == .makePermanent ? "Make It Permanent" : "Move the Window")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(purpose == .makePermanent ? "Make Permanent" : "Save") {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                        onConfirm(weekday, parts.hour ?? 20, parts.minute ?? 0)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents(purpose == .makePermanent ? [.large] : [.medium])
    }
}
