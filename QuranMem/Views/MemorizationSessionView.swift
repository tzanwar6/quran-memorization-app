import SwiftUI

struct MemorizationSessionView: View {
    let schedule: ScheduleWithSurah
    let onComplete: (PerformanceRating, String?) async -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var selectedRating: PerformanceRating?
    @State private var notes = ""
    @State private var isSubmitting = false
    @AppStorage(SchedulingPreferences.adjustForRatingKey) private var adjustForRating = SchedulingPreferences.default.adjustForRating

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.section) {
                    scheduleInfoCard
                    performanceRatingSection
                    notesSection
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, Metrics.card)
            }
            .background(Color.appCanvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Complete Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Complete") { submitSession() }
                        .fontWeight(.semibold)
                        .disabled(selectedRating == nil || isSubmitting)
                }
            }
        }
        // A light tick per rating change, the way a picker detent behaves.
        .sensoryFeedback(.selection, trigger: selectedRating)
    }

    private var scheduleInfoCard: some View {
        VStack(alignment: .leading, spacing: Metrics.card) {
            HStack(spacing: Metrics.card) {
                Image(systemName: "book.fill")
                    .font(.title3)
                    .foregroundStyle(Color.islamicGreen)
                    .frame(width: Metrics.minTarget, height: Metrics.minTarget)
                    .background(Color.islamicGreen.opacity(0.12), in: .circle)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule.surahArabicName)
                        .font(.title3.weight(.semibold))

                    Text(schedule.surahEnglishName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            ViewThatFits(in: .horizontal) {
                HStack { scopeLabels }
                VStack(alignment: .leading, spacing: 6) { scopeLabels }
            }
            .font(.subheadline)
        }
        .padding(Metrics.gutter)
        .cardSurface()
    }

    @ViewBuilder
    private var scopeLabels: some View {
        Label(
            schedule.isFullSurah
                ? "Full Surah (\(schedule.verseCount) verses)"
                : "Pages \(schedule.startPage ?? 0)–\(schedule.endPage ?? 0)",
            systemImage: "doc.text"
        )
        .foregroundStyle(.secondary)

        Spacer(minLength: 0)

        Label(schedule.frequency.displayName, systemImage: "calendar")
            .foregroundStyle(Color.islamicGreen)
    }

    private var performanceRatingSection: some View {
        VStack(alignment: .leading, spacing: Metrics.card) {
            SectionHeader(title: "How did it go?")

            VStack(spacing: 8) {
                ForEach(PerformanceRating.allCases, id: \.self) { rating in
                    RatingButton(
                        rating: rating,
                        isSelected: selectedRating == rating
                    ) {
                        selectedRating = rating
                    }
                }
            }

            if adjustForRating {
                Text(ratingScheduleHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .animation(.smooth(duration: 0.25), value: selectedRating)
            }
        }
    }

    private var ratingScheduleHint: String {
        switch selectedRating {
        case .veryPoor:
            return "This review will come back tomorrow."
        case .poor where schedule.frequency == .daily:
            return "This review will come back tomorrow."
        case .poor:
            return "This review will come back sooner than usual, after about half the normal interval."
        default:
            return "Poor or Very Poor ratings bring the review back sooner."
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Metrics.card) {
            SectionHeader(title: "Notes")

            NotesEditor(text: $notes, placeholder: "Anything worth remembering for next time")
        }
    }

    private func submitSession() {
        guard let rating = selectedRating else { return }

        isSubmitting = true

        Task {
            let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            await onComplete(rating, trimmedNotes.isEmpty ? nil : trimmedNotes)
            dismiss()
        }
    }
}

/// A text area that matches the surrounding card surfaces and shows a prompt
/// while it's empty, which a bare TextEditor doesn't do.
struct NotesEditor: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 110)
            .padding(10)
            .background(Color.appCard, in: .rect(cornerRadius: Metrics.controlRadius, style: .continuous))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Notes")
    }
}

struct RatingButton: View {
    let rating: PerformanceRating
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Metrics.card) {
                Circle()
                    .fill(rating.color)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text("\(rating.stars)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color(.systemBackground))
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rating.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(rating.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                StarRatingView(stars: rating.stars, size: .caption)
                    .accessibilityHidden(true)
            }
            .padding(Metrics.card)
            .frame(minHeight: Metrics.minTarget)
            .background(
                isSelected ? rating.color.opacity(0.12) : Color.appCard,
                in: .rect(cornerRadius: Metrics.controlRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                    .strokeBorder(
                        isSelected ? rating.color : Color(.separator),
                        lineWidth: isSelected ? 2 : 0.5
                    )
            }
        }
        .buttonStyle(.card)
        .animation(.snappy(duration: 0.25), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rating.displayName), \(rating.stars) of 5. \(rating.description)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
