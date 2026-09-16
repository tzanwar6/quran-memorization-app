import SwiftUI

struct SchedulesView: View {
    @StateObject private var viewModel = SchedulesViewModel()
    @State private var showingSurahSelection = false
    @State private var scheduleToDelete: ScheduleWithSurah?
    @State private var showDeleteConfirmation = false
    @State private var scheduleToEdit: ScheduleWithSurah?
    
    var body: some View {
        NavigationView {
            List {
                if viewModel.schedules.isEmpty && !viewModel.hasLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if viewModel.schedules.isEmpty {
                    emptyStateView
                } else {
                    ForEach(viewModel.schedules) { schedule in
                        ScheduleListRow(schedule: schedule) {
                            await viewModel.toggleScheduleActive(
                                id: schedule.id,
                                currentState: schedule.isActive
                            )
                        } onEdit: {
                            scheduleToEdit = schedule
                        } onDelete: {
                            scheduleToDelete = schedule
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle("Schedules")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSurahSelection = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await viewModel.loadData()
            }
            .task {
                await viewModel.loadData()
            }
        }
        .onChange(of: showingSurahSelection) { _, isShowing in
            if !isShowing {
                // Refresh data when modal is dismissed
                Task {
                    await viewModel.loadData()
                }
            }
        }
        .onChange(of: scheduleToEdit) { _, schedule in
            if schedule == nil {
                // Refresh data when edit modal is dismissed
                Task {
                    await viewModel.loadData()
                }
            }
        }
        .sheet(isPresented: $showingSurahSelection) {
            SurahSelectionView(
                surahs: viewModel.surahs,
                isPresented: $showingSurahSelection
            ) { surahId, frequency, isFullSurah, startPage, endPage in
                await viewModel.createSchedule(
                    surahId: surahId,
                    frequency: frequency,
                    isFullSurah: isFullSurah,
                    startPage: startPage,
                    endPage: endPage
                )
            }
        }
        .sheet(item: $scheduleToEdit) { schedule in
            EditFrequencyView(
                schedule: schedule
            ) { newFrequency, newDate in
                await viewModel.updateSchedule(
                    id: schedule.id,
                    frequency: newFrequency,
                    nextDueDate: newDate,
                    isActive: nil
                )
                scheduleToEdit = nil
            }
        }
        .alert("Delete Schedule", isPresented: $showDeleteConfirmation, presenting: scheduleToDelete) { schedule in
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteSchedule(id: schedule.id)
                }
            }
        } message: { schedule in
            Text(deleteMessage(for: schedule))
        }
        .errorAlert($viewModel.error)
    }
    
    private func deleteMessage(for schedule: ScheduleWithSurah) -> String {
        let question = "Are you sure you want to delete the schedule for \(schedule.surahEnglishName)?"
        switch viewModel.sessionCount(scheduleId: schedule.id) {
        case 0:
            return question
        case 1:
            return question + " Its 1 completed session will also be removed from your history and stats."
        case let count:
            return question + " Its \(count) completed sessions will also be removed from your history and stats."
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No Schedules Yet")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Tap the + button to create your first memorization schedule")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

struct ScheduleListRow: View {
    let schedule: ScheduleWithSurah
    let onToggle: () async -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(schedule.surahArabicName)
                        .font(.headline)
                    
                    Text(schedule.surahEnglishName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { schedule.isActive },
                    set: { _ in Task { await onToggle() } }
                ))
                .labelsHidden()
            }
            
            HStack(spacing: 16) {
                Label(schedule.frequency.displayName, systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(.islamicGreen)
                
                if !schedule.isFullSurah, let start = schedule.startPage, let end = schedule.endPage {
                    Label("Pages \(start)-\(end)", systemImage: "book")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Label("Full Surah", systemImage: "book.closed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(schedule.nextDueDate, style: .date)
                    .font(.caption)
                    .foregroundColor(schedule.isDueToday ? .red : .secondary)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
            
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

struct EditFrequencyView: View {
    let schedule: ScheduleWithSurah
    let onSave: (Frequency?, Date?) async -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedFrequency: Frequency
    @State private var selectedDate: Date
    @State private var shouldUpdateDate: Bool = false
    
    init(schedule: ScheduleWithSurah, onSave: @escaping (Frequency?, Date?) async -> Void) {
        self.schedule = schedule
        self.onSave = onSave
        self._selectedFrequency = State(initialValue: schedule.frequency)
        self._selectedDate = State(initialValue: schedule.nextDueDate)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(schedule.surahArabicName)
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text(schedule.surahEnglishName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Schedule")
                }
                
                Section {
                    Picker("Frequency", selection: $selectedFrequency) {
                        ForEach(Frequency.allCases, id: \.self) { frequency in
                            Text(frequency.displayName).tag(frequency)
                        }
                    }
                } header: {
                    Text("Review Frequency")
                } footer: {
                    Text("Changing the frequency will automatically update the next due date.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Next Due Date")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(schedule.nextDueDate, style: .date)
                            .font(.subheadline)
                        
                        if schedule.isOverdue {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text("OVERDUE")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                            }
                            .padding(.top, 4)
                        }
                    }
                } header: {
                    Text("Current Schedule")
                }
                
                Section {
                    Toggle("Manually Set Next Due Date", isOn: $shouldUpdateDate)
                        .tint(.islamicGreen)
                    
                    if shouldUpdateDate {
                        DatePicker(
                            "New Due Date",
                            selection: $selectedDate,
                            in: Date()...,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.graphical)
                    }
                } header: {
                    Text("Update Due Date")
                } footer: {
                    if shouldUpdateDate {
                        Text("Setting a new date will override the automatic frequency calculation. This is useful for adjusting your schedule or catching up on overdue items.")
                    } else {
                        Text("Enable this to manually set the next due date instead of using the automatic frequency calculation.")
                    }
                }
            }
            .navigationTitle("Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            // Pass only what changed; resending the same frequency would
                            // recalculate the due date and silently postpone the review.
                            let newFrequency = selectedFrequency == schedule.frequency ? nil : selectedFrequency
                            let newDate = shouldUpdateDate ? selectedDate : nil
                            if newFrequency != nil || newDate != nil {
                                await onSave(newFrequency, newDate)
                            }
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
