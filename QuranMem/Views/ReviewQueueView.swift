import SwiftUI

struct ReviewQueueView: View {
    @StateObject private var viewModel: ReviewQueueViewModel
    let previousNotes: [UUID: String]
    let nextReviewDate: () -> Date?
    let onComplete: (UUID, PerformanceRating, String?) async throws -> CompletedSession
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingExit = false

    init(schedules: [ScheduleWithSurah], previousNotes: [UUID: String], nextReviewDate: @escaping () -> Date?, onComplete: @escaping (UUID, PerformanceRating, String?) async throws -> CompletedSession) {
        _viewModel = StateObject(wrappedValue: ReviewQueueViewModel(schedules: schedules))
        self.previousNotes = previousNotes
        self.nextReviewDate = nextReviewDate
        self.onComplete = onComplete
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.section) {
                        Color.clear.frame(height: 0).id("reviewTop")
                        if let schedule = viewModel.current {
                            queueProgress
                            if viewModel.isRating {
                                SessionRatingContent(schedule: schedule, selectedRating: $viewModel.selectedRating, notes: $viewModel.notes)
                                    .disabled(viewModel.isSubmitting)
                            } else {
                                passage(schedule)
                            }
                        } else {
                            completion
                        }
                    }
                    .padding(Metrics.gutter)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: viewModel.index) { _, _ in proxy.scrollTo("reviewTop", anchor: .top) }
                .onChange(of: viewModel.isRating) { _, _ in proxy.scrollTo("reviewTop", anchor: .top) }
            }
            .background(Color.appCanvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(viewModel.isFinished ? "Reviews Complete" : viewModel.isRating ? "How Did It Go?" : "Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !viewModel.isFinished {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("End Review") {
                            if viewModel.hasDraft { confirmingExit = true } else { dismiss() }
                        }
                        .disabled(viewModel.isSubmitting)
                    }
                    if viewModel.isRating {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Passage") { viewModel.showPassage() }
                                .disabled(viewModel.isSubmitting)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
        }
        .interactiveDismissDisabled(viewModel.isSubmitting || viewModel.hasDraft)
        .errorAlert($viewModel.error, title: "Review Not Saved")
        .confirmationDialog("Leave this unfinished review?", isPresented: $confirmingExit, titleVisibility: .visible) {
            Button("Discard Draft & End", role: .destructive) { dismiss() }
        } message: {
            Text("Your saved reviews will be kept. This passage will remain due.")
        }
        .sensoryFeedback(.success, trigger: viewModel.completions.count)
    }

    private var queueProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review \(viewModel.index + 1) of \(viewModel.schedules.count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ProgressView(value: Double(viewModel.index), total: Double(max(1, viewModel.schedules.count)))
                .accessibilityLabel("Review queue")
                .accessibilityValue("\(viewModel.index) of \(viewModel.schedules.count) complete")
        }
    }

    private func passage(_ schedule: ScheduleWithSurah) -> some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            Text("Take a moment to recite")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            ReviewPassageCard(schedule: schedule)
            Text("Recite this passage from memory. Use your mushaf to check anything you’re unsure of, then record how it went.")
                .font(.body)
                .foregroundStyle(.secondary)
            if let note = previousNotes[schedule.id] {
                VStack(alignment: .leading, spacing: 8) {
                    Label("From Your Previous Reviews", systemImage: "note.text")
                        .font(.subheadline.weight(.semibold))
                    Text(note).font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Metrics.gutter)
                .cardSurface()
            }
            Button("Already reviewed? Log it now") { viewModel.showRating() }
                .frame(minHeight: Metrics.minTarget)
        }
    }

    private var completion: some View {
        VStack(spacing: Metrics.section) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Color.islamicGreen)
                .accessibilityHidden(true)
            Text("You’ve finished your reviews")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("\(viewModel.completions.count) \(viewModel.completions.count == 1 ? "passage" : "passages") reviewed. Your progress is saved.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let next = nextReviewDate() ?? viewModel.nextReviewDate {
                Label("Next review \(next.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    @ViewBuilder private var actionBar: some View {
        if viewModel.isFinished {
            ReviewActionBar(title: "Back to Today") { dismiss() }
        } else if viewModel.isRating {
            ReviewActionBar(
                title: viewModel.index + 1 == viewModel.schedules.count ? "Finish Reviews" : "Save & Next",
                isSubmitting: viewModel.isSubmitting,
                isDisabled: viewModel.selectedRating == nil
            ) {
                Task { await viewModel.submit(save: onComplete) }
            }
        } else {
            ReviewActionBar(title: "I’ve Finished Reciting") { viewModel.showRating() }
        }
    }
}

/// Keeps the primary action reachable while long notes and large text scroll.
struct ReviewActionBar: View {
    let title: String
    var isSubmitting = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isSubmitting { ProgressView() }
                Text(isSubmitting ? "Saving…" : title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: Metrics.minTarget)
            .foregroundStyle(Color(.systemBackground))
        }
        .buttonStyle(.borderedProminent)
        .disabled(isDisabled || isSubmitting)
        .padding(Metrics.gutter)
        .background(Color.appCanvas)
    }
}
