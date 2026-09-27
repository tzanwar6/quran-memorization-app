import SwiftUI
import Charts

// Named ProgressTabView so it doesn't shadow SwiftUI's ProgressView (the loading spinner).
struct ProgressTabView: View {
    @StateObject private var viewModel = ProgressViewModel()
    @State private var selectedTab = 0
    @State private var sessionToEdit: SessionWithSchedule?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.section) {
                    if let stats = viewModel.stats {
                        overviewSection(stats)
                    } else if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    }

                    Picker("View", selection: $selectedTab) {
                        Text("Charts").tag(0)
                        Text("History").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if selectedTab == 0 {
                        chartsSection
                    } else {
                        historySection
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 4)
                // Clears the floating tab bar.
                .padding(.bottom, Metrics.section)
            }
            .background(Color.appCanvas)
            .navigationTitle("Progress")
            .refreshable {
                await viewModel.loadData()
            }
            .task {
                await viewModel.loadData()
            }
        }
        .sheet(item: $sessionToEdit) { session in
            SessionEditView(
                session: session,
                onSave: { rating, notes in
                    await viewModel.updateSession(id: session.id, performanceRating: rating, notes: notes)
                },
                onDelete: {
                    await viewModel.deleteSession(id: session.id)
                }
            )
        }
        .errorAlert($viewModel.error)
    }

    // Four tiles in one neutral treatment. Giving each its own hue made the row
    // read as decoration; the numbers are the content, so they carry the weight
    // and the accent stays on the icons.
    private func overviewSection(_ stats: UserStatistics) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: Metrics.card),
                      GridItem(.flexible(), spacing: Metrics.card)],
            spacing: Metrics.card
        ) {
            ProgressStatCard(
                title: "Current Streak",
                value: "\(stats.currentStreak)",
                unit: stats.currentStreak == 1 ? "day" : "days",
                systemImage: "flame.fill"
            )
            ProgressStatCard(
                title: "Longest Streak",
                value: "\(stats.longestStreak)",
                unit: stats.longestStreak == 1 ? "day" : "days",
                systemImage: "trophy.fill"
            )
            ProgressStatCard(
                title: "Total Sessions",
                value: "\(stats.totalSessions)",
                unit: "completed",
                systemImage: "checkmark.circle.fill"
            )
            ProgressStatCard(
                title: "Average Rating",
                value: viewModel.averageRatingString,
                unit: "out of 5",
                systemImage: "star.fill"
            )
        }
    }

    private var chartsSection: some View {
        VStack(spacing: Metrics.section) {
            weeklyActivityChart
            performanceBreakdownChart
        }
    }

    private var weeklyActivityChart: some View {
        VStack(alignment: .leading, spacing: Metrics.card) {
            SectionHeader(title: "Last 7 Days")

            Chart(viewModel.last7DaysData, id: \.0) { data in
                BarMark(
                    x: .value("Date", data.0, unit: .day),
                    y: .value("Sessions", data.1),
                    width: .ratio(0.5)
                )
                .foregroundStyle(Color.islamicGreen)
                .cornerRadius(4)
            }
            // Without a floor the axis collapses to 0…0 on a quiet week and the
            // plot area reads as broken rather than empty.
            .chartYScale(domain: 0...max(1, viewModel.last7DaysData.map(\.1).max() ?? 1))
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine()
                    if let count = value.as(Int.self) {
                        AxisValueLabel { Text("\(count)") }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 180)
            .overlay {
                if viewModel.last7DaysData.allSatisfy({ $0.1 == 0 }) {
                    Text("No sessions this week")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(Metrics.gutter)
            .cardSurface()
            .accessibilityLabel("Sessions completed over the last 7 days")
        }
    }

    private var performanceBreakdownChart: some View {
        VStack(alignment: .leading, spacing: Metrics.card) {
            SectionHeader(title: "Performance")

            VStack(spacing: 10) {
                ForEach(viewModel.performanceBreakdown, id: \.0) { rating, count in
                    // Use the same sessions for the total as for the counts so the bars add up.
                    PerformanceBar(rating: rating, count: count, total: viewModel.sessions.count)
                }
            }
            .padding(Metrics.gutter)
            .cardSurface()
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Metrics.section) {
            if viewModel.sessions.isEmpty {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    ContentUnavailableView(
                        "No Sessions Yet",
                        systemImage: "chart.bar.doc.horizontal",
                        description: Text("Complete your first review to see your progress here.")
                    )
                    .padding(.vertical, 32)
                }
            } else {
                ForEach(viewModel.sessionsGroupedByDate, id: \.0) { date, sessions in
                    VStack(alignment: .leading, spacing: Metrics.card) {
                        SectionHeader(title: date.formatted(.dateTime.weekday(.wide).month().day()))

                        ForEach(sessions) { session in
                            Button {
                                sessionToEdit = session
                            } label: {
                                SessionHistoryRow(session: session)
                            }
                            .buttonStyle(.card)
                            .accessibilityHint("Opens the session to edit or delete it")
                        }
                    }
                }
            }
        }
    }
}

struct ProgressStatCard: View {
    let title: String
    let value: String
    let unit: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.gutter)
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value) \(unit)")
    }
}

struct PerformanceBar: View {
    let rating: PerformanceRating
    let count: Int
    let total: Int

    private var percentage: Double {
        total > 0 ? Double(count) / Double(total) : 0
    }

    var body: some View {
        HStack(spacing: Metrics.card) {
            Text(rating.displayName)
                .font(.caption)
                .frame(width: 76, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))

                    Capsule()
                        .fill(rating.color)
                        .frame(width: max(0, geometry.size.width * percentage))
                }
            }
            .frame(height: 14)

            Text("\(count)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rating.displayName): \(count) of \(total) sessions")
    }
}

struct SessionHistoryRow: View {
    let session: SessionWithSchedule

    var body: some View {
        HStack(spacing: Metrics.card) {
            // The number inside the dot carries the rating, so the colour is
            // reinforcement rather than the only signal.
            Circle()
                .fill(session.performanceRating.color)
                .frame(width: 34, height: 34)
                .overlay(
                    Text("\(session.performanceRating.stars)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color(.systemBackground))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.surahArabicName)
                    .font(.subheadline.weight(.medium))

                Text(session.surahEnglishName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let notes = session.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(session.completedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                StarRatingView(stars: session.performanceRating.stars)
            }
        }
        .padding(Metrics.card)
        .cardSurface()
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(session.surahEnglishName), \(session.performanceRating.displayName), \(session.completedAt.formatted(date: .omitted, time: .shortened))"
        )
    }
}
