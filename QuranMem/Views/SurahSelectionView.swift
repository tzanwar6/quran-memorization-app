import SwiftUI

struct SurahSelectionView: View {
    let surahs: [Surah]
    @Binding var isPresented: Bool
    let onCreate: (Int, Frequency, Bool, Int?, Int?) async -> Void

    @State private var searchText = ""
    @State private var selectedSurah: Surah?

    var filteredSurahs: [Surah] {
        if searchText.isEmpty {
            return surahs
        }
        return surahs.filter { surah in
            surah.englishName.localizedCaseInsensitiveContains(searchText) ||
            surah.arabicName.contains(searchText) ||
            surah.transliteration.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredSurahs.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    // A List lazily builds its rows; the previous ScrollView laid
                    // out all 114 surahs on every keystroke.
                    List(filteredSurahs) { surah in
                        Button {
                            selectedSurah = surah
                        } label: {
                            SurahSelectionRow(surah: surah)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Choose a Surah")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search surahs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
            .navigationDestination(item: $selectedSurah) { surah in
                ScheduleConfigurationView(surah: surah) { frequency, isFullSurah, startPage, endPage in
                    await onCreate(surah.id, frequency, isFullSurah, startPage, endPage)
                    isPresented = false
                }
            }
        }
    }
}

/// The second step of creating a schedule. Pushed rather than swapped in place so
/// the back button and the title say where you are.
struct ScheduleConfigurationView: View {
    let surah: Surah
    let onCreate: (Frequency, Bool, Int?, Int?) async -> Void

    @State private var frequency: Frequency = .daily
    @State private var isFullSurah = true
    @State private var startPage = ""
    @State private var endPage = ""
    @State private var isCreating = false

    /// Reported inline under the fields rather than in an alert after the fact,
    /// and it also gates the Create button — the error is prevented, not announced.
    private var validationError: String? {
        guard !isFullSurah else { return nil }
        guard let start = Int(startPage), let end = Int(endPage) else {
            return startPage.isEmpty && endPage.isEmpty ? nil : "Enter both page numbers."
        }
        guard start >= surah.pageStart, end <= surah.pageEnd else {
            return "This surah spans pages \(surah.pageStart)–\(surah.pageEnd)."
        }
        guard start <= end else {
            return "The start page must come before the end page."
        }
        return nil
    }

    private var canCreate: Bool {
        if isCreating { return false }
        if isFullSurah { return true }
        return validationError == nil && Int(startPage) != nil && Int(endPage) != nil
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(surah.arabicName)
                        .font(.title2.weight(.semibold))

                    Text(surah.englishName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: Metrics.card) {
                        Label("\(surah.verseCount) verses", systemImage: "book")
                        Label(surah.pageRange, systemImage: "doc.text")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section {
                Picker("Frequency", selection: $frequency) {
                    ForEach(Frequency.allCases, id: \.self) { freq in
                        Text(freq.displayName).tag(freq)
                    }
                }
            } header: {
                Text("Review Frequency")
            } footer: {
                Text("How often this passage comes back for review.")
            }

            Section {
                Toggle("Memorize Full Surah", isOn: $isFullSurah.animation(.snappy(duration: 0.3)))
                    .tint(.islamicGreen)

                if !isFullSurah {
                    LabeledContent("Start Page") {
                        TextField("\(surah.pageStart)", text: $startPage)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("End Page") {
                        TextField("\(surah.pageEnd)", text: $endPage)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                Text("Scope")
            } footer: {
                if let validationError {
                    Label(validationError, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                } else if !isFullSurah {
                    Text("Valid range: \(surah.pageStart)–\(surah.pageEnd).")
                }
            }
        }
        .navigationTitle("New Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    isCreating = true
                    Task {
                        await onCreate(frequency, isFullSurah, Int(startPage), Int(endPage))
                    }
                }
                .fontWeight(.semibold)
                .disabled(!canCreate)
            }
        }
    }
}

struct SurahSelectionRow: View {
    let surah: Surah

    var body: some View {
        HStack(spacing: Metrics.card) {
            Text("\(surah.id)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.islamicGreen)
                .frame(width: 38, height: 38)
                .background(Color.islamicGreen.opacity(0.12), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(surah.arabicName)
                        .font(.headline)

                    Spacer(minLength: 8)

                    Text(surah.revelation.capitalized)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: .capsule)
                }

                Text(surah.englishName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: Metrics.card) {
                    Label("\(surah.verseCount) verses", systemImage: "book")
                    Label(surah.pageRange, systemImage: "doc.text")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 1)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
