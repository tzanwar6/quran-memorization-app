import SwiftUI

struct MemorizationSessionView: View {
    let schedule: ScheduleWithSurah
    @Binding var isPresented: Bool
    let onComplete: (PerformanceRating, String?) async -> Void
    
    @State private var selectedRating: PerformanceRating?
    @State private var notes = ""
    @State private var isSubmitting = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    scheduleInfoCard
                    performanceRatingSection
                    notesSection
                }
                .padding()
            }
            .navigationTitle("Complete Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .disabled(isSubmitting)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Complete") {
                        submitSession()
                    }
                    .disabled(selectedRating == nil || isSubmitting)
                }
            }
        }
    }
    
    private var scheduleInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "book.fill")
                    .font(.title2)
                    .foregroundColor(.islamicGreen)
                    .frame(width: 44, height: 44)
                    .background(Color.islamicGreen.opacity(0.1))
                    .clipShape(Circle())
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(schedule.surahArabicName)
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    Text(schedule.surahEnglishName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            HStack {
                Label(
                    schedule.isFullSurah ?
                    "Full Surah (\(schedule.verseCount) verses)" :
                    "Pages \(schedule.startPage ?? 0)-\(schedule.endPage ?? 0)",
                    systemImage: "doc.text"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Label(schedule.frequency.displayName, systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundColor(.islamicGreen)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var performanceRatingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How did you perform?")
                .font(.headline)
            
            VStack(spacing: 12) {
                ForEach(PerformanceRating.allCases, id: \.self) { rating in
                    RatingButton(
                        rating: rating,
                        isSelected: selectedRating == rating
                    ) {
                        selectedRating = rating
                    }
                }
            }
        }
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Notes (Optional)")
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
    }
    
    private func submitSession() {
        guard let rating = selectedRating else { return }
        
        isSubmitting = true
        
        Task {
            await onComplete(rating, notes.isEmpty ? nil : notes)
            isPresented = false
        }
    }
}

struct RatingButton: View {
    let rating: PerformanceRating
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Circle()
                    .fill(ratingColor)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Text("\(rating.stars)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(rating.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(rating.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                starsView
            }
            .padding()
            .background(isSelected ? ratingColor.opacity(0.1) : Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? ratingColor : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var ratingColor: Color {
        switch rating {
        case .perfect: return .green
        case .veryGood: return .blue
        case .good: return .yellow
        case .poor: return .orange
        case .veryPoor: return .red
        }
    }
    
    private var starsView: some View {
        HStack(spacing: 3) {
            ForEach(0..<5) { index in
                Image(systemName: index < rating.stars ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundColor(index < rating.stars ? .goldAccent : .gray.opacity(0.3))
            }
        }
    }
}
