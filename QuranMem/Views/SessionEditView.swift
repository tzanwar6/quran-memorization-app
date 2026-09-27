import SwiftUI

struct SessionEditView: View {
    let session: SessionWithSchedule
    let onSave: (PerformanceRating, String?) async -> Void
    let onDelete: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRating: PerformanceRating
    @State private var notes: String
    @State private var isSubmitting = false
    @State private var showDeleteConfirmation = false

    init(
        session: SessionWithSchedule,
        onSave: @escaping (PerformanceRating, String?) async -> Void,
        onDelete: @escaping () async -> Void
    ) {
        self.session = session
        self.onSave = onSave
        self.onDelete = onDelete
        self._selectedRating = State(initialValue: session.performanceRating)
        self._notes = State(initialValue: session.notes ?? "")
    }

    private var trimmedNotes: String? {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var hasChanges: Bool {
        selectedRating != session.performanceRating || trimmedNotes != session.notes
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.section) {
                    header

                    VStack(alignment: .leading, spacing: Metrics.card) {
                        SectionHeader(title: "Rating")

                        VStack(spacing: 8) {
                            ForEach(PerformanceRating.allCases, id: \.self) { rating in
                                RatingButton(rating: rating, isSelected: selectedRating == rating) {
                                    selectedRating = rating
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Metrics.card) {
                        SectionHeader(title: "Notes")
                        NotesEditor(text: $notes, placeholder: "Anything worth remembering")
                    }

                    Text("Editing or deleting a past session updates your stats but doesn't move the schedule's due date. To change the date, edit the schedule.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Session", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Metrics.minTarget - 16)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSubmitting)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, Metrics.card)
            }
            .background(Color.appCanvas)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSubmitting = true
                        Task {
                            await onSave(selectedRating, trimmedNotes)
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!hasChanges || isSubmitting)
                }
            }
            .alert("Delete Session", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    isSubmitting = true
                    Task {
                        await onDelete()
                        dismiss()
                    }
                }
            } message: {
                Text("This removes the session from your history and stats.")
            }
        }
        .sensoryFeedback(.selection, trigger: selectedRating)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.surahArabicName)
                .font(.title3.weight(.semibold))
            Text(session.surahEnglishName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(session.completedAt, format: .dateTime.weekday(.wide).day().month().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.gutter)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }
}
