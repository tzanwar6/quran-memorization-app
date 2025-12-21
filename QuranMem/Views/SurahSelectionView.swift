import SwiftUI

struct SurahSelectionView: View {
    let surahs: [Surah]
    @Binding var isPresented: Bool
    let onCreate: (Int, Frequency, Bool, Int?, Int?) async -> Void
    
    @State private var searchText = ""
    @State private var selectedSurah: Surah?
    @State private var frequency: Frequency = .daily
    @State private var isFullSurah = true
    @State private var startPage = ""
    @State private var endPage = ""
    @State private var showValidationError = false
    @State private var validationMessage = ""
    
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
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    searchSection
                    
                    if selectedSurah == nil {
                        surahListSection
                    } else {
                        configurationSection
                    }
                }
                .padding()
            }
            .navigationTitle("Create Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                if selectedSurah != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Create") {
                            createSchedule()
                        }
                    }
                }
            }
            .alert("Validation Error", isPresented: $showValidationError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(validationMessage)
            }
        }
    }
    
    private var searchSection: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search Surahs", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
    
    private var surahListSection: some View {
        VStack(spacing: 8) {
            ForEach(filteredSurahs) { surah in
                SurahSelectionRow(surah: surah) {
                    selectedSurah = surah
                }
            }
        }
    }
    
    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let surah = selectedSurah {
                selectedSurahCard(surah)
                frequencyPicker
                fullSurahToggle
                
                if !isFullSurah {
                    pageRangeInputs(surah)
                }
            }
        }
    }
    
    private func selectedSurahCard(_ surah: Surah) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(surah.arabicName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(surah.englishName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Label("\(surah.verseCount) verses", systemImage: "book")
                        Label(surah.pageRange, systemImage: "doc.text")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Change") {
                    withAnimation {
                        selectedSurah = nil
                    }
                }
                .font(.caption)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var frequencyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frequency")
                .font(.headline)
            
            Picker("Frequency", selection: $frequency) {
                ForEach(Frequency.allCases, id: \.self) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }
            .pickerStyle(.segmented)
        }
    }
    
    private var fullSurahToggle: some View {
        Toggle("Memorize full Surah", isOn: $isFullSurah)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
    }
    
    private func pageRangeInputs(_ surah: Surah) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Page Range")
                .font(.headline)
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start Page")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("Start", text: $startPage)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("End Page")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("End", text: $endPage)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            Text("Valid range: \(surah.pageStart) - \(surah.pageEnd)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func createSchedule() {
        guard let surah = selectedSurah else { return }
        
        var startPageInt: Int?
        var endPageInt: Int?
        
        if !isFullSurah {
            guard let start = Int(startPage), let end = Int(endPage) else {
                validationMessage = "Please enter valid page numbers"
                showValidationError = true
                return
            }
            
            if start < surah.pageStart || end > surah.pageEnd || start > end {
                validationMessage = "Page range must be between \(surah.pageStart) and \(surah.pageEnd), and start page must be less than or equal to end page"
                showValidationError = true
                return
            }
            
            startPageInt = start
            endPageInt = end
        }
        
        Task {
            await onCreate(surah.id, frequency, isFullSurah, startPageInt, endPageInt)
            isPresented = false
        }
    }
}

struct SurahSelectionRow: View {
    let surah: Surah
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.islamicGreen.opacity(0.1))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text("\(surah.id)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.islamicGreen)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(surah.arabicName)
                            .font(.headline)
                        
                        Spacer()
                        
                        Text(surah.revelation.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color(.systemGray5))
                            .cornerRadius(4)
                    }
                    
                    Text(surah.englishName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Label("\(surah.verseCount) verses", systemImage: "book")
                        Label(surah.pageRange, systemImage: "doc.text")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
