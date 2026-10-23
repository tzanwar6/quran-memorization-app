import SwiftUI

extension PageState {
    var fill: Color {
        switch self {
        case .memorized: return .islamicGreen
        case .learning: return .islamicGreen.opacity(0.5)
        case .partlyKnown: return .islamicGreen.opacity(0.16)
        case .notStarted: return Color(.tertiarySystemFill)
        }
    }

    var name: String {
        switch self {
        case .memorized: return "Memorized"
        case .learning: return "Learning"
        case .partlyKnown: return "Partly known"
        case .notStarted: return "Not started"
        }
    }
}

/// One small square per page.
private struct PageCell: View {
    let state: PageState
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: max(1.5, size / 5), style: .continuous)
            .fill(state.fill)
            .overlay {
                // Partly known is the faintest fill, so it also gets an outline to tell it from empty.
                if state == .partlyKnown {
                    RoundedRectangle(cornerRadius: max(1.5, size / 5), style: .continuous)
                        .strokeBorder(Color.islamicGreen.opacity(0.5), lineWidth: 0.75)
                }
            }
            .frame(width: size, height: size)
    }
}

/// The whole mushaf at a glance: one row per juz, one cell per page.
struct QuranProgressMap: View {
    let states: [PageState]
    let planToday: HifzToday?
    let onSelectJuz: (Int) -> Void

    @State private var width: CGFloat = 320
    @ScaledMetric(relativeTo: .caption2) private var labelWidth: CGFloat = 20
    private let spacing: CGFloat = 2
    private static let widestJuz = (1...30).map { QuranPages.pages(inJuz: $0).count }.max() ?? 23

    private var memorizedCount: Int { states.filter { $0 == .memorized }.count }

    private var cellSize: CGFloat {
        let available = width - labelWidth - 6 - CGFloat(Self.widestJuz - 1) * spacing
        return min(14, max(5, (available / CGFloat(Self.widestJuz)).rounded(.down)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.card) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(memorizedCount)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text("of \(QuranPages.count) pages memorized")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(Double(memorizedCount) / Double(QuranPages.count), format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            ProgressView(value: Double(memorizedCount), total: Double(QuranPages.count))
                .tint(.islamicGreen)
                .accessibilityHidden(true)

            PageStateLegend()

            VStack(alignment: .leading, spacing: spacing + 1) {
                ForEach(1...30, id: \.self) { juz in
                    juzRow(juz)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }

            if let planToday {
                Divider()
                planRow(planToday)
            }
        }
        .padding(Metrics.gutter)
        .cardSurface()
    }

    private func juzRow(_ juz: Int) -> some View {
        let pages = QuranPages.pages(inJuz: juz)
        let rowStates = pages.map { states.indices.contains($0 - 1) ? states[$0 - 1] : .notStarted }
        let memorized = rowStates.filter { $0 == .memorized }.count
        let learning = rowStates.filter { $0 == .learning }.count

        return Button {
            onSelectJuz(juz)
        } label: {
            HStack(spacing: spacing) {
                Text("\(juz)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: labelWidth, alignment: .trailing)
                    .padding(.trailing, 6 - spacing)
                ForEach(Array(rowStates.enumerated()), id: \.offset) { _, state in
                    PageCell(state: state, size: cellSize)
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Juz \(juz)")
        .accessibilityValue(
            "\(memorized) of \(pages.count) pages memorized" + (learning > 0 ? ", \(learning) learning" : "")
        )
        .accessibilityHint("Shows the pages in this juz")
    }

    private func planRow(_ today: HifzToday) -> some View {
        let share = Double(today.memorizedCount) / Double(max(1, today.totalCount))
        return HStack(spacing: Metrics.card) {
            Image(systemName: "book.fill")
                .font(.subheadline)
                .foregroundStyle(Color.islamicGreen)
                .frame(width: 32, height: 32)
                .background(Color.islamicGreen.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(today.plan.title) · \(share.formatted(.percent.precision(.fractionLength(0))))")
                    .font(.subheadline.weight(.semibold))
                Text(planDetail(today))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func planDetail(_ today: HifzToday) -> String {
        if !today.plan.isActive { return "Paused" }
        if today.lesson == .finished { return "Every lesson memorized" }
        if let finish = today.projectedFinish {
            return "Done around \(finish.formatted(.dateTime.month(.abbreviated).day()))"
        }
        return "\(today.memorizedCount) of \(today.totalCount) half pages"
    }
}

struct PageStateLegend: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Metrics.card) { items }
            VStack(alignment: .leading, spacing: 4) { items }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var items: some View {
        ForEach([PageState.memorized, .learning, .partlyKnown, .notStarted], id: \.self) { state in
            HStack(spacing: 4) {
                PageCell(state: state, size: 9)
                Text(state.name)
            }
        }
    }
}

/// One juz up close: every page with its number, and the surahs in it.
struct JuzDetailView: View {
    let juz: Int
    let states: [PageState]
    let surahs: [Surah]
    @Environment(\.dismiss) private var dismiss

    private var pages: ClosedRange<Int> { QuranPages.pages(inJuz: juz) }

    private var surahsInJuz: [Surah] {
        surahs.filter { $0.pageEnd >= pages.lowerBound && $0.pageStart <= pages.upperBound }
    }

    private func state(_ page: Int) -> PageState {
        states.indices.contains(page - 1) ? states[page - 1] : .notStarted
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.section) {
                    VStack(alignment: .leading, spacing: Metrics.card) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                            ForEach(Array(pages), id: \.self) { page in
                                let pageState = state(page)
                                Text("\(page)")
                                    .font(.caption.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(pageState == .memorized ? Color(.systemBackground) : .primary)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(pageState.fill, in: .rect(cornerRadius: 8, style: .continuous))
                                    .overlay {
                                        if pageState == .partlyKnown {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(Color.islamicGreen.opacity(0.5), lineWidth: 1)
                                        }
                                    }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("Page \(page)")
                                    .accessibilityValue(pageState.name)
                            }
                        }
                        PageStateLegend()
                    }
                    .padding(Metrics.gutter)
                    .cardSurface()

                    VStack(alignment: .leading, spacing: Metrics.card) {
                        SectionHeader(title: "Surahs")
                        VStack(spacing: 0) {
                            ForEach(surahsInJuz) { surah in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(surah.arabicName).font(.headline)
                                        Text(surah.englishName).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(surah.pageRange)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 10)
                                .accessibilityElement(children: .combine)
                                if surah.id != surahsInJuz.last?.id { Divider() }
                            }
                        }
                        .padding(.horizontal, Metrics.gutter)
                        .cardSurface()
                    }
                }
                .padding(Metrics.gutter)
            }
            .background(Color.appCanvas)
            .navigationTitle("Juz \(juz)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
