import Foundation
import Combine

@MainActor
final class ReviewQueueViewModel: ObservableObject {
    let schedules: [ScheduleWithSurah]
    @Published private(set) var index = 0
    @Published private(set) var isRating = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var completions: [CompletedSession] = []
    @Published var selectedRating: PerformanceRating?
    @Published var notes = ""
    @Published var error: String?

    var current: ScheduleWithSurah? { schedules.indices.contains(index) ? schedules[index] : nil }
    var isFinished: Bool { current == nil }
    var hasDraft: Bool { selectedRating != nil || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var nextReviewDate: Date? { completions.map(\.nextDueDate).min() }

    init(schedules: [ScheduleWithSurah]) { self.schedules = schedules }

    func showRating() { isRating = true }
    func showPassage() { isRating = false }

    func submit(save: (UUID, PerformanceRating, String?) async throws -> CompletedSession) async {
        guard !isSubmitting, let current, let selectedRating else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        error = nil
        do {
            let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let completion = try await save(current.id, selectedRating, trimmed.isEmpty ? nil : trimmed)
            completions.append(completion)
            index += 1
            self.selectedRating = nil
            notes = ""
            isRating = false
        } catch {
            self.error = "Your review wasn’t saved. \(error.localizedDescription) Your rating and notes are still here; please try again."
        }
    }
}
