import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var selectedSchedule: ScheduleWithSurah?
    @State private var showSessionModal = false
    @State private var selectedDate: Date?
    @State private var showDateDetail = false
    
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
        .sheet(isPresented: $showSessionModal) {
            if let schedule = selectedSchedule {
                MemorizationSessionView(
                    schedule: schedule,
                    isPresented: $showSessionModal
                ) { rating, notes in
                    await viewModel.completeSession(
                        scheduleId: schedule.id,
                        performanceRating: rating,
                        notes: notes
                    )
                    showSessionModal = false
                    selectedSchedule = nil
                }
            }
        }
        .onChange(of: showSessionModal) { isShowing in
            if !isShowing {
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
            
            if viewModel.todaySchedules.isEmpty {
                emptyStateView
            } else {
                ForEach(viewModel.todaySchedules) { schedule in
                    ScheduleTaskCard(schedule: schedule) {
                        selectedSchedule = schedule
                        showSessionModal = true
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
                    selectedDate = date
                    showDateDetail = true
                }
            )
        }
        .sheet(isPresented: $showDateDetail) {
            if let date = selectedDate {
                DateDetailView(
                    date: date,
                    schedules: viewModel.calendarSchedules[date] ?? []
                )
            }
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

struct CalendarView: View {
    let schedules: [Date: [ScheduleWithSurah]]
    let onDateTap: (Date) -> Void
    
    private let calendar = Calendar.current
    private var today: Date {
        calendar.startOfDay(for: Date())
    }
    
    private var startDate: Date {
        // Start from the beginning of the week containing today
        let weekday = calendar.component(.weekday, from: today)
        let daysFromSunday = (weekday - 1) % 7
        return calendar.date(byAdding: .day, value: -daysFromSunday, to: today) ?? today
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
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
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

