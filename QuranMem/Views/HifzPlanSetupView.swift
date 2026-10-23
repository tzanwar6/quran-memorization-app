import SwiftUI

/// What the setup form produces, for creating a plan or saving changes to one.
struct HifzPlanDraft {
    var title: String
    var startPage: Int
    var endPage: Int
    var halvesPerDay: Int
    var lessonWeekdays: Int16
    var recentReviewCount: Int
    var revisionFrequency: Frequency
}

/// Setting up a memorization plan, or changing the pace of the current one.
struct HifzPlanSetupView: View {
    enum Mode {
        case create
        /// The range is fixed once a plan has started; only its pace can change.
        case edit(HifzPlan)
    }

    let mode: Mode
    let surahs: [Surah]
    /// Set when saving will end a plan that's still under way.
    var replacingPlanTitle: String?
    let onSave: (HifzPlanDraft) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var presetId = HifzPlanPreset.all[0].id
    @State private var customFrom = 67
    @State private var customTo = 77
    @State private var halvesPerDay = 1
    @State private var lessonWeekdays = HifzPlan.allWeekdays
    @State private var recentReviewCount = 14
    @State private var revisionFrequency: Frequency = .weekly
    @State private var isSaving = false
    @State private var error: String?

    private static let customId = "custom"

    init(mode: Mode, surahs: [Surah], replacingPlanTitle: String? = nil, onSave: @escaping (HifzPlanDraft) async throws -> Void) {
        self.mode = mode
        self.surahs = surahs
        self.replacingPlanTitle = replacingPlanTitle
        self.onSave = onSave
        if case .edit(let plan) = mode {
            _halvesPerDay = State(initialValue: plan.halvesPerDay)
            _lessonWeekdays = State(initialValue: plan.lessonWeekdays)
            _recentReviewCount = State(initialValue: plan.recentReviewCount)
            _revisionFrequency = State(initialValue: plan.revisionFrequency)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var range: HifzPlanPreset? {
        if case .edit(let plan) = mode {
            return HifzPlanPreset(id: "current", title: plan.title, startPage: plan.startPage, endPage: plan.endPage)
        }
        if presetId == Self.customId {
            guard let from = surahs.first(where: { $0.id == customFrom }),
                  let to = surahs.first(where: { $0.id == customTo }) else { return nil }
            return .custom(from: from, to: to)
        }
        return HifzPlanPreset.all.first { $0.id == presetId }
    }

    /// The plan as it would be saved, for the summary.
    private var preview: HifzPlan? {
        range.map {
            HifzPlan(
                id: UUID(), title: $0.title, startPage: $0.startPage, endPage: $0.endPage,
                halvesPerDay: halvesPerDay, lessonWeekdays: lessonWeekdays, recentReviewCount: recentReviewCount,
                revisionFrequency: revisionFrequency, isActive: true, completedAt: nil, createdAt: Date()
            )
        }
    }

    private var canSave: Bool { range != nil && lessonWeekdays & HifzPlan.allWeekdays != 0 && !isSaving }

    var body: some View {
        NavigationStack {
            Form {
                rangeSection
                paceSection
                afterLearningSection
            }
            .navigationTitle(isEditing ? "Edit Plan" : "New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Start") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .errorAlert($error, title: "Plan Not Saved")
    }

    @ViewBuilder
    private var rangeSection: some View {
        if case .edit(let plan) = mode {
            Section {
                LabeledContent("Plan", value: plan.title)
                LabeledContent("Pages", value: "\(plan.startPage)–\(plan.endPage)")
            } header: {
                Text("What to Memorize")
            } footer: {
                Text("To memorize a different range, end this plan from Schedules and start a new one.")
            }
        } else {
            Section {
                ForEach(HifzPlanPreset.all) { preset in
                    choiceRow(title: preset.title, detail: pagesDetail(preset), id: preset.id)
                }
                choiceRow(title: "Custom Range", detail: "Between any two surahs", id: Self.customId)

                if presetId == Self.customId {
                    Picker("From", selection: $customFrom) {
                        ForEach(surahs) { Text("\($0.id). \($0.englishName)").tag($0.id) }
                    }
                    Picker("To", selection: $customTo) {
                        ForEach(surahs) { Text("\($0.id). \($0.englishName)").tag($0.id) }
                    }
                }
            } header: {
                Text("What to Memorize")
            } footer: {
                let notes = [
                    range.flatMap { $0.startPage > $0.endPage ? "Runs backward a page at a time, learning each page from the top." : nil },
                    replacingPlanTitle.map { "Starting this plan ends \($0). Portions still in recent review move to revision now." },
                ].compactMap { $0 }
                if !notes.isEmpty {
                    Text(notes.joined(separator: " "))
                }
            }
        }
    }

    private var paceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Each lesson")
                Picker("Each lesson", selection: $halvesPerDay) {
                    Text("½ page").tag(1)
                    Text("1 page").tag(2)
                    Text("1½").tag(3)
                    Text("2 pages").tag(4)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Lesson days")
                WeekdayToggles(mask: $lessonWeekdays)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Pace")
        } footer: {
            if lessonWeekdays & HifzPlan.allWeekdays == 0 {
                Label("Choose at least one lesson day.", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
            } else {
                Text("Rest days skip the new lesson. Recent review stays daily.")
            }
        }
    }

    private var afterLearningSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent review for")
                Picker("Recent review for", selection: $recentReviewCount) {
                    ForEach(HifzPlan.recentReviewOptions, id: \.self) { Text("\($0) days").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, 4)

            Picker("Then revise", selection: $revisionFrequency) {
                ForEach(Frequency.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
        } header: {
            Text("After Learning")
        } footer: {
            Text(summary)
        }
    }

    private var summary: String {
        guard let preview else { return "" }
        let explanation = "Each half page is recited daily in recent review until it has \(recentReviewCount) good reviews, then it moves to your revision schedules."
        guard lessonWeekdays & HifzPlan.allWeekdays != 0 else { return explanation }

        let days = (1...7).filter { HifzPlan.weekdayIsSet($0, in: lessonWeekdays) }.count
        let pace = days == 7 ? "\(preview.amountDescription) a day" : "\(preview.amountDescription) a day, \(days) days a week"
        let recentPages = preview.typicalRecentPages.formatted(.number.precision(.fractionLength(0)))
        var text = "\(pace). Recent review stays around \(recentPages) \(recentPages == "1" ? "page" : "pages")."
        if !isEditing {
            let firstDay = preview.isLessonDay(Date()) ? Date() : preview.nextLessonDay(after: Date())
            if let firstDay, let finish = preview.projectedFinish(remaining: preview.totalHalves, from: firstDay) {
                text += " You’ll finish learning around \(finish.formatted(.dateTime.month(.abbreviated).day().year()))."
            }
        }
        return "\(text) \(explanation)"
    }

    private func pagesDetail(_ preset: HifzPlanPreset) -> String {
        let pages = abs(preset.endPage - preset.startPage) + 1
        return "Pages \(preset.startPage)–\(preset.endPage) · \(pages) pages"
    }

    private func choiceRow(title: String, detail: String, id: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { presetId = id }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if presetId == id {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.islamicGreen)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(presetId == id ? .isSelected : [])
    }

    private func save() {
        guard let range, canSave else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await onSave(HifzPlanDraft(
                    title: range.title, startPage: range.startPage, endPage: range.endPage,
                    halvesPerDay: halvesPerDay, lessonWeekdays: lessonWeekdays,
                    recentReviewCount: recentReviewCount, revisionFrequency: revisionFrequency
                ))
                dismiss()
            } catch {
                self.error = "\(error.localizedDescription) Your choices are still here; please try again."
            }
        }
    }
}

/// Seven round toggles, one per weekday, starting on the locale's first day of the week.
struct WeekdayToggles: View {
    @Binding var mask: Int16
    private let calendar = Calendar.current

    private var weekdays: [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(weekdays, id: \.self) { weekday in
                let isOn = HifzPlan.weekdayIsSet(weekday, in: mask)
                Button {
                    mask ^= Int16(1 << (weekday - 1))
                } label: {
                    Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOn ? Color(.systemBackground) : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isOn ? Color.islamicGreen : Color(.tertiarySystemFill), in: .circle)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: mask)
    }
}
