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
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.surahArabicName)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(session.surahEnglishName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(session.completedAt, format: .dateTime.weekday(.wide).day().month().hour().minute())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Rating")
                            .font(.headline)

                        ForEach(PerformanceRating.allCases, id: \.self) { rating in
                            RatingButton(rating: rating, isSelected: selectedRating == rating) {
                                selectedRating = rating
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notes")
                            .font(.headline)

                        TextEditor(text: $notes)
                            .frame(height: 100)
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                    }

                    Text("Editing or deleting a past session updates your stats but doesn't move the schedule's due date. To change the date, edit the schedule.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Session", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSubmitting)
                }
                .padding()
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
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
    }
}
