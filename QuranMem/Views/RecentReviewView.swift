import SwiftUI

/// Reciting everything learned recently, as one block, and rating how it went.
struct RecentReviewView: View {
    let plan: HifzPlan
    let block: HifzToday.RecentBlock
    let surahNames: String
    let previousNote: String?
    let nextToMove: (half: HalfPage, reviewsLeft: Int)?
    let onSave: (PerformanceRating, String?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRating: PerformanceRating?
    @State private var notes = ""
    @State private var isSubmitting = false
    @State private var error: String?
    @State private var confirmingExit = false

    private var hasDraft: Bool { selectedRating != nil || !notes.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.section) {
                    PassageCard(
                        symbol: "arrow.triangle.2.circlepath",
                        title: block.halves.pageRangeDescription,
                        subtitle: "\(surahNames) · \(HifzTodayCard.halves(block.halfCount))",
                        details: [PassageCard.Detail(text: learnedRange, symbol: "calendar")]
                    )

                    Text("Recite everything you’ve learned recently, from memory and in order. Check anything you’re unsure of in your mushaf, then record how it went.")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    if let previousNote {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("From Your Previous Reviews", systemImage: "note.text")
                                .font(.subheadline.weight(.semibold))
                            Text(previousNote).font(.body)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Metrics.gutter)
                        .cardSurface()
                    }

                    VStack(alignment: .leading, spacing: Metrics.card) {
                        SectionHeader(title: "How did it go?")
                        RatingChoices(selectedRating: $selectedRating)
                        Text(movingHint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: Metrics.card) {
                        SectionHeader(title: "Notes")
                        NotesEditor(text: $notes, placeholder: "Anything worth remembering for next time")
                    }
                }
                .sensoryFeedback(.selection, trigger: selectedRating)
                .disabled(isSubmitting)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, Metrics.card)
            }
            .background(Color.appCanvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Recent Review")
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
                ReviewActionBar(title: "Save Review", isSubmitting: isSubmitting, isDisabled: selectedRating == nil) { submit() }
            }
            .ignoresKeyboardSafeAreaWhenHidden()
        }
        .interactiveDismissDisabled(isSubmitting || hasDraft)
        .errorAlert($error, title: "Review Not Saved")
        .confirmationDialog("Discard this review?", isPresented: $confirmingExit, titleVisibility: .visible) {
            Button("Discard Review", role: .destructive) { dismiss() }
        }
    }

    private var learnedRange: String {
        let style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        let first = block.firstLearned.formatted(style)
        let last = block.lastLearned.formatted(style)
        return first == last ? "Learned \(first)" : "Learned \(first) – \(last)"
    }

    private var movingHint: String {
        var hint = "Each half page moves to revision after \(plan.recentReviewCount) recent reviews rated Good or better."
        if let nextToMove {
            // Today's review counts from tomorrow, so one left means it moves tomorrow.
            let when = nextToMove.reviewsLeft == 1
                ? "tomorrow, if this review goes well"
                : "after \(nextToMove.reviewsLeft) more good reviews, counting this one"
            hint += " Next to move: page \(nextToMove.half.page), \(when)."
        }
        return hint
    }

    private func submit() {
        guard let rating = selectedRating, !isSubmitting else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                try await onSave(rating, trimmed.isEmpty ? nil : trimmed)
                dismiss()
            } catch {
                self.error = "\(error.localizedDescription) Your rating and notes are still here; please try again."
            }
        }
    }
}
