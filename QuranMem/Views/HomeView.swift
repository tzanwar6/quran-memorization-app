import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var selectedSchedule: ScheduleWithSurah?
    @State private var selectedDay: CalendarDaySelection?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    todayTasksSection
                    
                    calendarSection
                }
                .padding()
            }
            .navigationTitle("QuranMem")
            .refreshable {
                await viewModel.loadData()
            }
            .task {
                await viewModel.loadData()
            }
        }
        // sheet(item:) rather than sheet(isPresented:): the content of an isPresented sheet can be
        // built before the accompanying state lands, which shows an empty sheet the first time.
        .sheet(item: $selectedSchedule) { schedule in
            MemorizationSessionView(schedule: schedule) { rating, notes in
                await viewModel.completeSession(
                    scheduleId: schedule.id,
                    performanceRating: rating,
                    notes: notes
                )
            }
        }
        .overlay(alignment: .bottom) {
            if let completed = viewModel.lastCompleted {
                UndoBanner(completed: completed) {
                    Task {
                        await viewModel.undoLastSession()
                    }
                }
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: completed.sessionId) {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    withAnimation {
                        viewModel.dismissUndo(for: completed)
                    }
                }
            }
        }
        .animation(.easeInOut, value: viewModel.lastCompleted)
        .errorAlert($viewModel.error)
        .onChange(of: selectedSchedule) { _, schedule in
            if schedule == nil {
                // Refresh data when modal is dismissed
                Task {
                    await viewModel.loadData()
                }
            }
        }
    }
    
    private var todayTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today's Tasks")
                .font(.headline)
                .foregroundColor(.primary)
            
            if viewModel.todaySchedules.isEmpty && !viewModel.hasLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else if viewModel.todaySchedules.isEmpty {
                emptyStateView
            } else {
                ForEach(viewModel.todaySchedules) { schedule in
                    ScheduleTaskCard(schedule: schedule) {
                        selectedSchedule = schedule
                    }
                }
            }
        }
    }
    
    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming Schedule")
                .font(.headline)
                .foregroundColor(.primary)
            
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
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No tasks due today")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Great job staying on track!")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
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
        let symbols = calendar.shortWeekdaySymbols
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
        VStack(spacing: 0) {
            // Week day headers
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 8)
            
            // Calendar grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
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
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct CalendarDayView: View {
    let date: Date
    let schedules: [ScheduleWithSurah]
    let isToday: Bool
    let isPast: Bool
    let onTap: () -> Void
    
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 13, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? .white : (isPast ? .secondary : .primary))
                .frame(width: 26, height: 26)
                .background(isToday ? Color.islamicGreen : Color.clear)
                .clipShape(Circle())
            
            if !schedules.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(schedules) { schedule in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(schedule.surahEnglishName)
                                .font(.system(size: 8))
                                .fontWeight(.medium)
                                .foregroundColor(isPast ? .secondary : .primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            if schedule.isOverdue && !isPast {
                                Text("OVERDUE")
                                    .font(.system(size: 6))
                                    .fontWeight(.bold)
                                    .foregroundColor(.red)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: 80)
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .opacity(isPast ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}

struct DateDetailView: View {
    let date: Date
    let schedules: [ScheduleWithSurah]
    @Environment(\.dismiss) private var dismiss
    
    private let calendar = Calendar.current
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }
    
    private var isToday: Bool {
        calendar.isDateInToday(date)
    }
    
    private var isPast: Bool {
        date < calendar.startOfDay(for: Date())
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Date header
                    VStack(alignment: .leading, spacing: 4) {
                        Text(dateFormatter.string(from: date))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        if isToday {
                            Text("Today")
                                .font(.subheadline)
                                .foregroundColor(.islamicGreen)
                                .fontWeight(.semibold)
                        } else if isPast {
                            Text("Past Date")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    
                    Divider()
                    
                    // Schedules list
                    if schedules.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "calendar")
                                .font(.system(size: 48))
                                .foregroundColor(.gray.opacity(0.5))
                            
                            Text("No schedules for this day")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(schedules) { schedule in
                                ScheduleDetailCard(schedule: schedule, isPast: isPast)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Schedule Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ScheduleDetailCard: View {
    let schedule: ScheduleWithSurah
    let isPast: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(schedule.surahArabicName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(schedule.surahEnglishName)
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            HStack(spacing: 16) {
                Label(schedule.frequency.displayName, systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundColor(.islamicGreen)
                
                if schedule.isFullSurah {
                    Label("Full Surah", systemImage: "book.closed")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if let start = schedule.startPage, let end = schedule.endPage {
                    Label("Pages \(start)-\(end)", systemImage: "book")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            if schedule.isOverdue && !isPast {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("OVERDUE")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct ScheduleTaskCard: View {
    let schedule: ScheduleWithSurah
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(schedule.surahArabicName)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(schedule.surahEnglishName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Label(schedule.frequency.displayName, systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.islamicGreen)
                        
                        if schedule.isOverdue {
                            Text("OVERDUE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct UndoBanner: View {
    let completed: CompletedSession
    let onUndo: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.islamicGreen)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(completed.surahEnglishName) completed")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Next review \(completed.nextDueDate.formatted(.dateTime.weekday(.wide).month().day()))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button("Undo", action: onUndo)
                .fontWeight(.semibold)
                .foregroundColor(.islamicGreen)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}
