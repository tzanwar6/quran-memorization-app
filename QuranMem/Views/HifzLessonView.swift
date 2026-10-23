import SwiftUI

/// Memorizing today's new lesson from the mushaf, then marking it memorized.
struct HifzLessonView: View {
    let plan: HifzPlan
    let halves: [HalfPage]
    let memorizedCount: Int
    let surahNames: String
    let onMemorize: (String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var repetitions = 0
    @State private var notes = ""
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var confirmingExit = false

    private var hasDraft: Bool { repetitions > 0 || !notes.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.section) {
                    PassageCard(
                        symbol: "book.fill",
                        title: halves.portionDescription,
                        subtitle: surahNames,
                        details: [
                            PassageCard.Detail(text: "Juz \(QuranPages.juz(forPage: halves.first?.page ?? 1))", symbol: "bookmark"),
                            PassageCard.Detail(text: "\(memorizedCount) of \(plan.totalHalves) half pages done", symbol: "chart.bar", isAccent: true),
                        ]
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text(instruction)
                            .font(.body)
                        Text("Take it an ayah at a time: recite each one from memory several times, then join it to the ones before it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    repetitionCounter

                    VStack(alignment: .leading, spacing: Metrics.card) {
                        SectionHeader(title: "Notes")
                        NotesEditor(text: $notes, placeholder: "Ayahs that sound alike, or where you stumbled")
                    }
                }
                .disabled(isSubmitting)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, Metrics.card)
            }
            .background(Color.appCanvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New Lesson")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasDraft { confirmingExit = true } else { dismiss() }
                    }
                    .disabled(isSubmitting)
                }
            }
            .safeAreaInset(edge: .bottom) {
                ReviewActionBar(title: "Mark as Memorized", isSubmitting: isSubmitting) { submit() }
            }
            .ignoresKeyboardSafeAreaWhenHidden()
        }
        .interactiveDismissDisabled(isSubmitting || hasDraft)
        .errorAlert($error, title: "Lesson Not Saved")
        .confirmationDialog("Leave this lesson?", isPresented: $confirmingExit, titleVisibility: .visible) {
            Button("Leave Without Saving", role: .destructive) { dismiss() }
        } message: {
            Text("The lesson stays on Home until you mark it memorized.")
        }
    }

    private var instruction: String {
        guard let first = halves.first else { return "" }
        if halves.count == 1 {
            return "Open your mushaf to page \(first.page) and memorize the \(first.half.name)."
        }
        let portion = halves.portionDescription
        return "Open your mushaf to page \(first.page) and memorize \(portion.prefix(1).lowercased() + portion.dropFirst())."
    }

    /// A tap counter for recitations. Only on screen; it isn't saved.
    private var repetitionCounter: some View {
        VStack(spacing: Metrics.card) {
            Text("Repetitions")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(repetitions)")
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityHidden(true)

            Button {
                withAnimation(.snappy(duration: 0.2)) { repetitions += 1 }
            } label: {
                Text("+1")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Color.islamicGreen)
                    .frame(width: 88, height: 88)
                    .background(Color.islamicGreen.opacity(0.12), in: .circle)
            }
            .buttonStyle(.card)
            .accessibilityLabel("Count a recitation")
            .accessibilityValue("\(repetitions) so far")
            .sensoryFeedback(.increase, trigger: repetitions)

            HStack(spacing: 4) {
                Text("Tap after each recitation.")
                    .foregroundStyle(.secondary)
                if repetitions > 0 {
                    Button("Reset") { withAnimation(.snappy(duration: 0.2)) { repetitions = 0 } }
                        .tint(.islamicGreen)
                }
            }
            .font(.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding(Metrics.gutter)
        .cardSurface()
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                try await onMemorize(trimmed.isEmpty ? nil : trimmed)
                dismiss()
            } catch {
                self.error = "\(error.localizedDescription) Your notes are still here; please try again."
            }
        }
    }
}
