import SwiftUI
import Charts

// Named ProgressTabView so it doesn't shadow SwiftUI's ProgressView (the loading spinner).
struct ProgressTabView: View {
    @StateObject private var viewModel = ProgressViewModel()
    @State private var selectedTab = 0
    @State private var sessionToEdit: SessionWithSchedule?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
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
                    .padding(.horizontal)

                    if selectedTab == 0 {
                        chartsSection
                    } else {
                        historySection
                    }
                }
                .padding(.vertical)
            }
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

    private func overviewSection(_ stats: UserStatistics) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ProgressStatCard(
                    title: "Current Streak",
                    value: "\(stats.currentStreak)",
                    subtitle: "days",
                    color: .orange
                )

                ProgressStatCard(
                    title: "Longest Streak",
                    value: "\(stats.longestStreak)",
                    subtitle: "days",
                    color: .blue
                )
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                ProgressStatCard(
                    title: "Total Sessions",
                    value: "\(stats.totalSessions)",
                    subtitle: "completed",
                    color: .islamicGreen
                )

                ProgressStatCard(
                    title: "Average Rating",
                    value: viewModel.averageRatingString,
                    subtitle: "out of 5",
                    color: .goldAccent
                )
            }
            .padding(.horizontal)
        }
    }

    private var chartsSection: some View {
        VStack(spacing: 24) {
            weeklyActivityChart
            performanceBreakdownChart
        }
        .padding(.horizontal)
    }

    private var weeklyActivityChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days Activity")
                .font(.headline)
                .padding(.horizontal)

            Chart(viewModel.last7DaysData, id: \.0) { data in
                BarMark(
                    x: .value("Date", data.0, unit: .day),
                    y: .value("Sessions", data.1)
                )
                .foregroundStyle(Color.islamicGreen)
            }
            .frame(height: 200)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    private var performanceBreakdownChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Breakdown")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 8) {
                ForEach(viewModel.performanceBreakdown, id: \.0) { rating, count in
                    // Use the same sessions for the total as for the counts so the bars add up.
                    PerformanceBar(rating: rating, count: count, total: viewModel.sessions.count)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.sessions.isEmpty {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else {
                    emptyHistoryView
                }
            } else {
                Text("Tap a session to edit or delete it.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                ForEach(viewModel.sessionsGroupedByDate, id: \.0) { date, sessions in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(date, style: .date)
                            .font(.headline)
                            .foregroundColor(.islamicGreen)
                            .padding(.horizontal)

                        ForEach(sessions) { session in
                            Button {
                                sessionToEdit = session
                            } label: {
                                SessionHistoryRow(session: session)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
    }

    private var emptyHistoryView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.5))

            Text("No Sessions Yet")
                .font(.headline)

            Text("Complete your first memorization session to see your progress here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

struct ProgressStatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(color)

            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4)
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
        HStack(spacing: 12) {
            Text(rating.displayName)
                .font(.caption)
                .foregroundColor(.primary)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 20)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(rating.color)
                        .frame(width: geometry.size.width * percentage, height: 20)
                }
            }
            .frame(height: 20)

            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }
}

struct SessionHistoryRow: View {
    let session: SessionWithSchedule

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(session.performanceRating.color)
                .frame(width: 32, height: 32)
                .overlay(
                    Text("\(session.performanceRating.stars)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(session.surahArabicName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(session.surahEnglishName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let notes = session.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(session.completedAt, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)

                starsView
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .contentShape(Rectangle())
    }

    private var starsView: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                Image(systemName: index < session.performanceRating.stars ? "star.fill" : "star")
                    .font(.caption2)
                    .foregroundColor(.goldAccent)
            }
        }
    }
}
