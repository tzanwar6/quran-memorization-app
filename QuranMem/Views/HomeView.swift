import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    let onManageSchedules: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var presentation: HomePresentation?
    @State private var selectedDay: CalendarDaySelection?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.section) {
                    todaySection
                    if viewModel.allSchedules.contains(where: \.isActive) {
                        calendarSection
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 4)
                // Clears the floating tab bar so the last card isn't trapped under it.
                .padding(.bottom, Metrics.section)
            }
            .background(Color.appCanvas)
            .navigationTitle("QuranMem")
            .refreshable {
                await viewModel.loadData()
            }
            .task {
                await viewModel.loadData()
            }
        }
        .sheet(item: $presentation, onDismiss: {
            Task { await viewModel.loadData() }
        }) { destination in
            switch destination {
            case .queue(let schedules):
                ReviewQueueView(
                    schedules: schedules,
                    previousNotes: viewModel.previousNotes,
                    nextReviewDate: { viewModel.dailySummary.nextReviewDate }
                ) { id, rating, notes in
                    try await viewModel.completeSession(scheduleId: id, performanceRating: rating, notes: notes)
                }
            case .quickLog(let schedule):
                MemorizationSessionView(schedule: schedule) { rating, notes in
                    try await viewModel.completeSession(scheduleId: schedule.id, performanceRating: rating, notes: notes)
                }
            case .create:
                SurahSelectionView(surahs: viewModel.surahs, isPresented: Binding(
                    get: { presentation != nil },
                    set: { if !$0 { presentation = nil } }
                )) { id, frequency, fullSurah, start, end in
                    try await viewModel.createSchedule(surahId: id, frequency: frequency, isFullSurah: fullSurah, startPage: start, endPage: end)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if presentation == nil, let completed = viewModel.lastCompleted {
                UndoBanner(completed: completed) {
                    Task {
                        await viewModel.undoLastSession()
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, Metrics.card)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: completed.sessionId) {
                    do { try await Task.sleep(nanoseconds: 8_000_000_000) }
                    catch { return }
                    withAnimation(.smooth(duration: 0.35)) {
                        viewModel.dismissUndo(for: completed)
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.35), value: viewModel.lastCompleted)
        // A completed review is the outcome of a multi-step task, so it earns the
        // success notification rather than a plain tap impact. Dismissal is silent.
        .sensoryFeedback(trigger: viewModel.lastCompleted) { _, new in
            new == nil ? nil : .success
        }
        .errorAlert($viewModel.error)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.loadData() } }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            Task { await viewModel.loadData() }
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: Metrics.card) {
            SectionHeader(title: "Today")
            if !viewModel.hasLoaded {
                if viewModel.loadFailed {
                    ContentUnavailableView {
                        Label("Couldn’t Load Reviews", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    } description: {
                        Text("Try again to see your saved progress.")
                    } actions: {
                        Button("Try Again") { Task { await viewModel.loadData() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
                }
            } else if viewModel.dailySummary.state == .reviewsDue {
                dailySummaryCard
                Text("Ready to Review")
                    .font(.headline)
                    .padding(.top, Metrics.card)
                    .accessibilityAddTraits(.isHeader)
                Text("Tap a passage to log a review you’ve already completed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(viewModel.todaySchedules) { schedule in
                    ScheduleTaskCard(schedule: schedule) {
                        presentation = .quickLog(schedule)
                    }
                }
            } else {
                emptyState
            }
        }
    }

    private var dailySummaryCard: some View {
        let summary = viewModel.dailySummary
        return VStack(alignment: .leading, spacing: Metrics.card) {
            Text("\(summary.completedCount) of \(summary.totalCount) reviews complete")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("dailySummary")
            ProgressView(value: Double(summary.completedCount), total: Double(max(1, summary.totalCount)))
                .accessibilityLabel("Today’s progress")
                .accessibilityValue("\(summary.completedCount) of \(summary.totalCount) reviews complete")
            Text("\(summary.remaining.count) \(summary.remaining.count == 1 ? "passage is" : "passages are") ready for your attention.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                presentation = .queue(viewModel.todaySchedules)
            } label: {
                Label(summary.completedCount > 0 ? "Continue Review" : "Start Review", systemImage: "play.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: Metrics.minTarget)
                    .foregroundStyle(Color(.systemBackground))
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("startReview")
        }
        .padding(Metrics.gutter)
        .cardSurface()
    }

    @ViewBuilder private var emptyState: some View {
        let summary = viewModel.dailySummary
        switch summary.state {
        case .gettingStarted:
            HomeEmptyState(title: "Begin Your Review Rhythm", symbol: "book.closed", message: "Choose a surah you’re memorizing. We’ll help you keep it fresh, one review at a time.", actionTitle: "Choose Your First Surah") {
                presentation = .create
            }
        case .finished:
            HomeEmptyState(title: "Today’s Reviews Are Complete", symbol: "checkmark.circle.fill", message: "\(summary.completedCount) \(summary.completedCount == 1 ? "passage" : "passages") reviewed today. \(nextReviewMessage)", actionTitle: "Manage Schedules", action: onManageSchedules)
        case .quietDay:
            HomeEmptyState(title: "A Quiet Day", symbol: "calendar", message: "Nothing is due today. \(nextReviewMessage)", actionTitle: "Manage Schedules", action: onManageSchedules)
        case .paused:
            HomeEmptyState(title: "Your Reviews Are Paused", symbol: "pause.circle", message: "Turn on a schedule when you’re ready to return. Your review history is still here.", actionTitle: "Manage Schedules", action: onManageSchedules)
        case .reviewsDue:
            EmptyView()
        }
    }

    private var nextReviewMessage: String {
        if let next = viewModel.dailySummary.nextReviewDate {
            return "Your next review is \(next.formatted(date: .abbreviated, time: .omitted))."
        }
        return "You can manage your review rhythm in Schedules."
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: Metrics.card) {
            SectionHeader(title: "Next Two Weeks")

            CalendarView(
                schedules: viewModel.calendarSchedules,
                onDateTap: { date in
                    selectedDay = CalendarDaySelection(date: date)
                }
            )
        }
        .sheet(item: $selectedDay) { day in
            DateDetailView(
                date: day.date,
                schedules: viewModel.calendarSchedules[day.date] ?? []
            )
        }
    }
}

/// Wraps the tapped day so the sheet receives the date as its item.
struct CalendarDaySelection: Identifiable {
    let date: Date
    var id: Date { date }
}

struct CalendarView: View {
    let schedules: [Date: [ScheduleWithSurah]]
    let onDateTap: (Date) -> Void

    private let calendar = Calendar.current
    private var today: Date {
        calendar.startOfDay(for: Date())
    }

    private var startDate: Date {
        // Start from the beginning of the week containing today, using the region's first weekday
        let weekday = calendar.component(.weekday, from: today)
        let daysFromWeekStart = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysFromWeekStart, to: today) ?? today
    }

    private var weekdaySymbols: [String] {
        // Very-short symbols keep seven columns legible on the narrowest iPhone.
        let symbols = calendar.veryShortWeekdaySymbols
        let firstIndex = calendar.firstWeekday - 1
        return Array(symbols[firstIndex...] + symbols[..<firstIndex])
    }

    private var endDate: Date {
        // 2 weeks (14 days) from start
        calendar.date(byAdding: .day, value: 13, to: startDate) ?? startDate
    }

    private var dates: [Date] {
        var dates: [Date] = []
        var currentDate = startDate
        while currentDate <= endDate {
            dates.append(currentDate)
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
        }
        return dates
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(dates, id: \.self) { date in
                    CalendarDayView(
                        date: date,
                        schedules: schedules[date] ?? [],
                        isToday: calendar.isDateInToday(date),
                        isPast: date < today,
                        onTap: {
                            onDateTap(date)
                        }
                    )
                }
            }
        }
        // Seven fixed columns can't reflow, so the day numbers collide at the top
        // accessibility sizes. Cap the grid's scaling rather than let it break;
        // the day sheet behind each cell has no cap and carries the full detail.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(Metrics.card)
        .cardSurface()
    }
}

struct CalendarDayView: View {
    let date: Date
    let schedules: [ScheduleWithSurah]
    let isToday: Bool
    let isPast: Bool
    let onTap: () -> Void

    private let calendar = Calendar.current
    // Grows with the type size so the marker never crowds its number.
    @ScaledMetric(relativeTo: .callout) private var markerSize: CGFloat = 30

    private var overdueCount: Int {
        schedules.filter { $0.isOverdue && !isPast }.count
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                Text(date, format: .dateTime.day())
                    .font(.callout)
                    .fontWeight(isToday ? .semibold : .regular)
                    .monospacedDigit()
                    .foregroundStyle(numberStyle)
                    .frame(width: markerSize, height: markerSize)
                    .background {
                        if isToday {
                            Circle().fill(Color.islamicGreen)
                        }
                    }

                DueDots(total: schedules.count, overdue: overdueCount)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Metrics.minTarget)
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.card)
        .opacity(isPast ? 0.4 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    private var numberStyle: Color {
        // systemBackground is the counterpart to the accent fill in both
        // appearances: white on the deep light-mode green, black on the lifted
        // dark-mode one. A literal .white would sit at about 2:1 in dark mode.
        if isToday { return Color(.systemBackground) }
        return isPast ? Color(.tertiaryLabel) : .primary
    }

    private var accessibilityLabel: String {
        var parts = [date.formatted(.dateTime.weekday(.wide).month(.wide).day())]
        if isToday { parts.append("Today") }

        switch schedules.count {
        case 0: parts.append("No reviews")
        case 1: parts.append("1 review")
        case let count: parts.append("\(count) reviews")
        }

        if overdueCount > 0 {
            parts.append("\(overdueCount) overdue")
        }
        return parts.joined(separator: ", ")
    }
}

/// A day's review load, shown as a small run of dots. Overdue items lead in red.
/// The names themselves live in the day sheet — at seven columns wide there is no
/// width for a surah name that a reader could actually use.
private struct DueDots: View {
    let total: Int
    let overdue: Int

    @ScaledMetric(relativeTo: .caption2) private var dot: CGFloat = 5
    private let maxDots = 3

    var body: some View {
        HStack(spacing: 3) {
            if total == 0 {
                Color.clear
            } else {
                ForEach(0..<min(total, maxDots), id: \.self) { index in
                    Circle()
                        .fill(index < overdue ? Color.red : Color.islamicGreen)
                        .frame(width: dot, height: dot)
                }
                if total > maxDots {
                    Text("+\(total - maxDots)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: dot + 3)
    }
}

struct DateDetailView: View {
    let date: Date
    let schedules: [ScheduleWithSurah]
    @Environment(\.dismiss) private var dismiss

    private let calendar = Calendar.current

    private var isToday: Bool {
        calendar.isDateInToday(date)
    }

    private var isPast: Bool {
        date < calendar.startOfDay(for: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.card) {
                    if schedules.isEmpty {
                        ContentUnavailableView(
                            "Nothing Scheduled",
                            systemImage: "calendar",
                            description: Text("No reviews fall on this day.")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(schedules) { schedule in
                            ScheduleDetailCard(schedule: schedule, isPast: isPast)
                        }
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, Metrics.card)
            }
            .background(Color.appCanvas)
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).month().day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(date, format: .dateTime.weekday(.wide).month().day())
                            .font(.headline)
                        if isToday {
                            Text("Today")
                                .font(.caption)
                                .foregroundStyle(Color.islamicGreen)
                        } else if isPast {
                            Text("Past")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct ScheduleDetailCard: View {
    let schedule: ScheduleWithSurah
    let isPast: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.card) {
            VStack(alignment: .leading, spacing: 2) {
                Text(schedule.surahArabicName)
                    .font(.title3.weight(.semibold))

                Text(schedule.surahEnglishName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Wraps to a second line instead of truncating at large type sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Metrics.gutter) { scopeLabels }
                VStack(alignment: .leading, spacing: 6) { scopeLabels }
            }

            if schedule.isOverdue && !isPast {
                OverdueBadge()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.gutter)
        .cardSurface()
    }

    @ViewBuilder
    private var scopeLabels: some View {
        Label(schedule.frequency.displayName, systemImage: "calendar")
            .font(.subheadline)
            .foregroundStyle(Color.islamicGreen)

        if schedule.isFullSurah {
            Label("Full Surah", systemImage: "book.closed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if let start = schedule.startPage, let end = schedule.endPage {
            Label("Pages \(start)–\(end)", systemImage: "book")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct ScheduleTaskCard: View {
    let schedule: ScheduleWithSurah
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Metrics.card) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(schedule.surahArabicName)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(schedule.surahEnglishName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Side by side until the type size makes them too wide, at
                    // which point they stack — otherwise "Weekly" and the badge
                    // hyphenate mid-word at the accessibility sizes.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { metadata }
                        VStack(alignment: .leading, spacing: 6) { metadata }
                    }
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(Metrics.gutter)
            .cardSurface()
        }
        .buttonStyle(.card)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Log a review you’ve already completed")
    }

    @ViewBuilder
    private var metadata: some View {
        Label(schedule.scopeDescription, systemImage: "book.closed")
            .font(.caption)
            .foregroundStyle(.secondary)


        Label(schedule.frequency.displayName, systemImage: "calendar")
            .font(.caption)
            .foregroundStyle(Color.islamicGreen)

        if schedule.isOverdue {
            OverdueBadge()
        }
    }
}

struct UndoBanner: View {
    let completed: CompletedSession
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Metrics.card) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.islamicGreen)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(completed.surahEnglishName) completed")
                    .font(.subheadline.weight(.medium))

                Text("Next review \(completed.nextDueDate.formatted(.dateTime.weekday(.wide).month().day()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .tint(.islamicGreen)
        }
        .padding(Metrics.card)
        // Floating chrome over content is exactly where a system material belongs.
        .background(.regularMaterial, in: .rect(cornerRadius: Metrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }
}

private enum HomePresentation: Identifiable {
    case create
    case quickLog(ScheduleWithSurah)
    case queue([ScheduleWithSurah])

    var id: String {
        switch self {
        case .create: return "create"
        case .quickLog(let schedule): return "log-\(schedule.id)"
        case .queue: return "queue"
        }
    }
}

private struct HomeEmptyState: View {
    let title: String
    let symbol: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: Metrics.card) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(Color.islamicGreen)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .frame(minHeight: Metrics.minTarget)
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(Metrics.section)
        .cardSurface()
    }
}
