import SwiftUI

struct SchedulesView: View {
    @StateObject private var viewModel = SchedulesViewModel()
    @State private var showingSurahSelection = false
    @State private var scheduleToDelete: ScheduleWithSurah?
    @State private var showDeleteConfirmation = false
    @State private var scheduleToEdit: ScheduleWithSurah?
    @State private var planSheet: PlanSheet?
    @State private var confirmingEndPlan = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.schedules.isEmpty && !viewModel.hasLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.schedules.isEmpty && viewModel.plan == nil {
                    ContentUnavailableView {
                        Label("No Schedules Yet", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("Add a surah you know to start a review rhythm, or start a plan to memorize something new.")
                    } actions: {
                        Button("Create Schedule") { showingSurahSelection = true }
                            .buttonStyle(.borderedProminent)
                        Button("Start Memorizing") { planSheet = .create }
                            .buttonStyle(.bordered)
                    }
                } else {
                    List {
                        Section("Memorization Plan") {
                            if let today = viewModel.hifzToday {
                                PlanSummaryRow(today: today) {
                                    planSheet = .edit(today.plan)
                                } onTogglePause: {
                                    Task { await viewModel.setPlanActive(!today.plan.isActive) }
                                } onEnd: {
                                    confirmingEndPlan = true
                                }
                            } else {
                                Button {
                                    planSheet = .create
                                } label: {
                                    Label("Start a Memorization Plan", systemImage: "book")
                                }
                                .tint(.islamicGreen)
                            }
                        }

                        if !viewModel.schedules.isEmpty {
                            Section("Revision") {
                                scheduleRows
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Schedules")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSurahSelection = true
                    } label: {
                        Label("New Schedule", systemImage: "plus")
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
            ) { surahId, frequency, isFullSurah, startPage, endPage, startsOn in
                try await viewModel.createSchedule(
                    surahId: surahId,
                    frequency: frequency,
                    isFullSurah: isFullSurah,
                    startPage: startPage,
                    endPage: endPage,
                    startsOn: startsOn
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
        .sheet(item: $planSheet, onDismiss: {
            Task { await viewModel.loadData() }
        }) { sheet in
            switch sheet {
            case .create:
                HifzPlanSetupView(mode: .create, surahs: viewModel.surahs) { draft in
                    try await viewModel.createPlan(draft)
                }
            case .edit(let plan):
                HifzPlanSetupView(mode: .edit(plan), surahs: viewModel.surahs) { draft in
                    try await viewModel.savePlan(draft)
                }
            }
        }
        .confirmationDialog(
            "End \(viewModel.plan?.title ?? "this plan")?",
            isPresented: $confirmingEndPlan,
            titleVisibility: .visible
        ) {
            Button("End Plan", role: .destructive) {
                Task { await viewModel.endPlan() }
            }
        } message: {
            Text("Everything you’ve memorized moves to revision now, including portions still in recent review. You can start a new plan afterwards.")
        }
        .errorAlert($viewModel.error)
        .errorAlert($viewModel.lockNotice, title: "Log the Review First")
        .errorAlert($viewModel.planNotice, title: "Plan Ended")
    }

    private var scheduleRows: some View {
        ForEach(viewModel.schedules) { schedule in
            ScheduleListRow(schedule: schedule) {
                await viewModel.toggleScheduleActive(
                    id: schedule.id,
                    currentState: schedule.isActive
                )
            } onEdit: {
                guard !viewModel.blocksChange(to: schedule) else { return }
                scheduleToEdit = schedule
            } onDelete: {
                guard !viewModel.blocksChange(to: schedule) else { return }
                scheduleToDelete = schedule
                showDeleteConfirmation = true
            }
        }
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
}

private enum PlanSheet: Identifiable {
    case create
    case edit(HifzPlan)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let plan): return "edit-\(plan.id)"
        }
    }
}

/// The current memorization plan at the top of Schedules: its pace, progress and controls.
struct PlanSummaryRow: View {
    let today: HifzToday
    let onEdit: () -> Void
    let onTogglePause: () -> Void
    let onEnd: () -> Void

    private var plan: HifzPlan { today.plan }

    private var progressLine: String {
        var line = "\(today.memorizedCount) of \(today.totalCount) half pages"
        if !plan.isActive {
            line += " · paused"
        } else if today.lesson != .finished, let finish = today.projectedFinish {
            line += " · done around \(finish.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.title)
                    .font(.headline)
                Text("\(plan.amountDescription) a day · \(plan.lessonDaysDescription) · \(plan.recentReviewCount)-day recent review")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: Double(today.memorizedCount), total: Double(max(1, today.totalCount)))
                .tint(.islamicGreen)
                .accessibilityLabel("Plan progress")
                .accessibilityValue(progressLine)

            Text(progressLine)
                .font(.caption)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { controls }
                VStack(alignment: .leading, spacing: 8) { controls }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var controls: some View {
        Button("Edit", action: onEdit)
            .buttonStyle(.bordered)
            .tint(.islamicGreen)
        Button(plan.isActive ? "Pause" : "Resume", action: onTogglePause)
            .buttonStyle(.bordered)
            .tint(.islamicGreen)
        Button("End Plan", role: .destructive, action: onEnd)
            .buttonStyle(.bordered)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule.surahArabicName)
                        .font(.headline)

                    Text(schedule.surahEnglishName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // The label is hidden visually but still read by VoiceOver, which
                // an empty-string toggle would not be.
                Toggle("Active", isOn: Binding(
                    get: { schedule.isActive },
                    set: { _ in Task { await onToggle() } }
                ))
                .labelsHidden()
                .tint(.islamicGreen)
            }

            // Wraps rather than truncating once the type size grows.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Metrics.card) { metadata }
                VStack(alignment: .leading, spacing: 4) { metadata }
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
        .opacity(schedule.isActive ? 1 : 0.55)
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

    @ViewBuilder
    private var metadata: some View {
        Label(schedule.frequency.displayName, systemImage: "calendar")
            .foregroundStyle(Color.islamicGreen)

        if !schedule.isFullSurah, let start = schedule.startPage, let end = schedule.endPage {
            Label(start == end ? "Page \(start)" : "Pages \(start)–\(end)", systemImage: "book")
                .foregroundStyle(.secondary)
        } else {
            Label("Full Surah", systemImage: "book.closed")
                .foregroundStyle(.secondary)
        }

        if schedule.isFromPlan {
            Text("Plan")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.islamicGreen)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color.islamicGreen.opacity(0.12), in: .capsule)
                .accessibilityLabel("From your memorization plan")
        }

        Spacer(minLength: 0)

        dueLabel
    }

    /// Overdue is called out by name and icon, not by colour alone; a review that
    /// is merely due today stays neutral so the red keeps its meaning.
    @ViewBuilder
    private var dueLabel: some View {
        if schedule.isOverdue {
            Label("Overdue", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .fontWeight(.semibold)
        } else if schedule.startsLater {
            Text("Starts \(schedule.nextDueDate.formatted(.dateTime.month().day()))")
                .foregroundStyle(.secondary)
        } else if Calendar.current.isDateInToday(schedule.nextDueDate) {
            Text("Due today")
                .foregroundStyle(Color.islamicGreen)
                .fontWeight(.medium)
        } else {
            Text(schedule.nextDueDate, format: .dateTime.month().day())
                .foregroundStyle(.secondary)
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
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(schedule.surahArabicName)
                            .font(.title3.weight(.semibold))

                        Text(schedule.surahEnglishName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    LabeledContent(schedule.startsLater ? "Starts" : "Next Due") {
                        Text(schedule.nextDueDate, format: .dateTime.weekday().month().day())
                    }

                    if schedule.isOverdue {
                        OverdueBadge()
                    }
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
                    Toggle("Set Date Manually", isOn: $shouldUpdateDate)
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
            .animation(.snappy(duration: 0.3), value: shouldUpdateDate)
            .navigationTitle("Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
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
