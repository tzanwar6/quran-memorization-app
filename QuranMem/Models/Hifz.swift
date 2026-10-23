import Foundation

// A memorization plan moves through a page range half a page at a time. Each half is a new lesson
// (sabaq) on the day it's memorized, then joins the daily recent review (sabqi) until it has been
// recited well enough times, and then moves to revision (manzil): the ordinary schedules.

/// The top or bottom half of a mushaf page, the step a memorization plan moves in.
struct HalfPage: Hashable, Comparable {
    enum Half: Int16 {
        case top = 0
        case bottom = 1

        var name: String { self == .top ? "top half" : "bottom half" }
    }

    let page: Int
    let half: Half

    static func < (lhs: HalfPage, rhs: HalfPage) -> Bool {
        (lhs.page, lhs.half.rawValue) < (rhs.page, rhs.half.rawValue)
    }
}

extension Array where Element == HalfPage {
    /// "Page 568 · top half", "Page 568", "Pages 568–569", or "Page 568 + page 569 top half",
    /// grouping halves by page in the order given.
    var portionDescription: String {
        var groups: [(page: Int, halves: [HalfPage.Half])] = []
        for half in self {
            if let last = groups.indices.last, groups[last].page == half.page {
                groups[last].halves.append(half.half)
            } else {
                groups.append((half.page, [half.half]))
            }
        }
        guard let first = groups.first else { return "" }

        if groups.count == 1 {
            return first.halves.count == 2 ? "Page \(first.page)" : "Page \(first.page) · \(first.halves[0].name)"
        }
        let pages = groups.map(\.page)
        let wholePages = groups.allSatisfy { $0.halves.count == 2 }
        if wholePages, let low = pages.min(), let high = pages.max(), high - low + 1 == pages.count {
            return "Pages \(low)–\(high)"
        }
        return groups.enumerated().map { index, group in
            let page = index == 0 ? "Page \(group.page)" : "page \(group.page)"
            return group.halves.count == 2 ? page : "\(page) \(group.halves[0].name)"
        }.joined(separator: " + ")
    }

    /// The page range these halves touch, in mushaf order: "Page 565" or "Pages 565–567".
    var pageRangeDescription: String {
        guard let low = map(\.page).min(), let high = map(\.page).max() else { return "" }
        return low == high ? "Page \(low)" : "Pages \(low)–\(high)"
    }
}

struct HifzPlan: Identifiable, Equatable {
    static let allWeekdays: Int16 = 0b111_1111
    static let halvesPerDayOptions = [1, 2, 3, 4]
    static let recentReviewOptions = [7, 14, 30]

    let id: UUID
    var title: String
    /// First page in learning order. A start after the end means the plan runs backward.
    var startPage: Int
    var endPage: Int
    var halvesPerDay: Int
    /// One bit per weekday: bit 0 is Sunday (`Calendar` weekday 1).
    var lessonWeekdays: Int16
    /// Good recent reviews a half needs before it moves to revision.
    var recentReviewCount: Int
    var revisionFrequency: Frequency
    var isActive: Bool
    var completedAt: Date?
    var createdAt: Date

    var isBackward: Bool { startPage > endPage }

    /// Every half in the plan, in the order it will be learned. A backward plan steps back a page
    /// at a time but still learns each page from the top.
    var orderedHalves: [HalfPage] {
        let pages = isBackward ? Array(stride(from: startPage, through: endPage, by: -1)) : Array(startPage...endPage)
        return pages.flatMap { [HalfPage(page: $0, half: .top), HalfPage(page: $0, half: .bottom)] }
    }

    var totalHalves: Int { (abs(endPage - startPage) + 1) * 2 }

    /// The distinct pages given, in the order the plan learns them.
    func pagesInOrder(_ pages: [Int]) -> [Int] {
        Set(pages).sorted { isBackward ? $0 > $1 : $0 < $1 }
    }

    func isLessonDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        Self.weekdayIsSet(calendar.component(.weekday, from: date), in: lessonWeekdays)
    }

    static func weekdayIsSet(_ weekday: Int, in mask: Int16) -> Bool {
        mask & (1 << (weekday - 1)) != 0
    }

    /// The first lesson day after `date`, or nil if no weekday is a lesson day.
    func nextLessonDay(after date: Date, calendar: Calendar = .current) -> Date? {
        guard lessonWeekdays & Self.allWeekdays != 0 else { return nil }
        var day = calendar.startOfDay(for: date)
        for _ in 0..<7 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
            if isLessonDay(day, calendar: calendar) { return day }
        }
        return nil
    }

    /// The day the last of `remaining` halves would be learned, counting lesson days from `firstDay`.
    func projectedFinish(remaining: Int, from firstDay: Date, calendar: Calendar = .current) -> Date? {
        guard remaining > 0, halvesPerDay > 0, lessonWeekdays & Self.allWeekdays != 0 else { return nil }
        var left = remaining
        var day = calendar.startOfDay(for: firstDay)
        for _ in 0..<5_000 {
            if isLessonDay(day, calendar: calendar) {
                left -= halvesPerDay
                if left <= 0 { return day }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
        }
        return nil
    }

    /// About how many pages recent review settles at once lessons have been going for a while.
    var typicalRecentPages: Double {
        let lessonDays = (1...7).filter { Self.weekdayIsSet($0, in: lessonWeekdays) }.count
        let halves = Double(halvesPerDay) * Double(recentReviewCount) * Double(lessonDays) / 7
        return min(halves, Double(totalHalves)) / 2
    }

    var amountDescription: String {
        switch halvesPerDay {
        case 1: return "½ page"
        case 2: return "1 page"
        case 3: return "1½ pages"
        default: return "\(Double(halvesPerDay) / 2) pages"
        }
    }

    /// "Every day", "Sat–Thu", or "Mon, Wed, Fri".
    var lessonDaysDescription: String {
        Self.weekdaysDescription(lessonWeekdays)
    }

    static func weekdaysDescription(_ mask: Int16, calendar: Calendar = .current) -> String {
        let days = (1...7).filter { weekdayIsSet($0, in: mask) }
        if days.count == 7 { return "Every day" }
        if days.isEmpty { return "No lesson days" }
        let symbols = calendar.shortWeekdaySymbols
        // A run that wraps past Saturday, like Sat–Thu, is found by starting after the first gap.
        if days.count >= 3, let gap = (1...7).first(where: { !weekdayIsSet($0, in: mask) }) {
            let order = (0..<7).map { (gap + $0) % 7 + 1 }.filter { weekdayIsSet($0, in: mask) }
            let isRun = zip(order, order.dropFirst()).allSatisfy { ($0 % 7) + 1 == $1 }
            if isRun, let first = order.first, let last = order.last {
                return "\(symbols[first - 1])–\(symbols[last - 1])"
            }
        }
        return days.map { symbols[$0 - 1] }.joined(separator: ", ")
    }
}

struct HifzLesson: Identifiable, Equatable {
    let id: UUID
    let planId: UUID
    let halfPage: HalfPage
    let memorizedAt: Date
    let notes: String?
    let graduatedAt: Date?
}

struct HifzReview: Identifiable, Equatable {
    let id: UUID
    let planId: UUID
    let completedAt: Date
    let performanceRating: PerformanceRating
    let notes: String?
    let firstPage: Int
    let lastPage: Int
    let halfCount: Int

    var pageRangeDescription: String {
        firstPage == lastPage ? "Page \(firstPage)" : "Pages \(firstPage)–\(lastPage)"
    }
}

/// What a memorization plan asks for today. The hifz counterpart of `DailyReviewSummary`.
struct HifzToday {
    enum Lesson: Equatable {
        /// Today's portion, not yet memorized.
        case due([HalfPage])
        /// Today's lesson is memorized; the next portion comes on `nextDay`.
        case done(next: [HalfPage], nextDay: Date?)
        case restDay(next: [HalfPage], nextDay: Date?)
        /// Every half in the plan has been memorized.
        case finished
    }

    /// Everything memorized before today that hasn't moved to revision yet, recited as one block.
    struct RecentBlock: Equatable {
        let halves: [HalfPage]
        let firstLearned: Date
        let lastLearned: Date

        var firstPage: Int { halves.map(\.page).min() ?? 0 }
        var lastPage: Int { halves.map(\.page).max() ?? 0 }
        var halfCount: Int { halves.count }
    }

    let plan: HifzPlan
    let lesson: Lesson
    let recentBlock: RecentBlock?
    let recentReviewDoneToday: Bool
    /// Something was memorized today, so it joins recent review tomorrow.
    let learnedToday: Bool
    let memorizedCount: Int
    let projectedFinish: Date?
    /// Today's good recent reviews count toward the move only from tomorrow.
    let goodReviewsByHalf: [HalfPage: Int]

    var totalCount: Int { plan.totalHalves }
    var isPaused: Bool { !plan.isActive }

    var isLessonDue: Bool {
        if case .due = lesson { return plan.isActive }
        return false
    }

    var isRecentReviewDue: Bool { plan.isActive && recentBlock != nil && !recentReviewDoneToday }

    /// Lessons and recent reviews still to do today: for the badge and the Revision Lock.
    var pendingCount: Int { (isLessonDue ? 1 : 0) + (isRecentReviewDue ? 1 : 0) }

    /// The half in recent review closest to moving to revision, and how many more good reviews it needs.
    var nextToMove: (half: HalfPage, reviewsLeft: Int)? {
        guard let block = recentBlock else { return nil }
        return block.halves
            .map { ($0, max(1, plan.recentReviewCount - (goodReviewsByHalf[$0] ?? 0))) }
            .min { $0.1 < $1.1 }
    }

    init(plan: HifzPlan, lessons: [HifzLesson], reviews: [HifzReview], now: Date = Date(), calendar: Calendar = .current) {
        self.plan = plan
        let today = calendar.startOfDay(for: now)
        let planLessons = lessons.filter { $0.planId == plan.id }
        let planReviews = reviews.filter { $0.planId == plan.id }
        let memorized = Set(planLessons.map(\.halfPage))
        let remaining = plan.orderedHalves.filter { !memorized.contains($0) }
        let next = Array(remaining.prefix(plan.halvesPerDay))
        let memorizedToday = planLessons.contains { calendar.isDate($0.memorizedAt, inSameDayAs: now) }

        if remaining.isEmpty {
            lesson = .finished
        } else if memorizedToday {
            lesson = .done(next: next, nextDay: plan.nextLessonDay(after: today, calendar: calendar))
        } else if !plan.isLessonDay(today, calendar: calendar) {
            lesson = .restDay(next: next, nextDay: plan.nextLessonDay(after: today, calendar: calendar))
        } else {
            lesson = .due(next)
        }

        let order = Dictionary(uniqueKeysWithValues: plan.orderedHalves.enumerated().map { ($1, $0) })
        let inBlock = planLessons
            .filter { $0.graduatedAt == nil && calendar.startOfDay(for: $0.memorizedAt) < today }
            .sorted { (order[$0.halfPage] ?? 0) < (order[$1.halfPage] ?? 0) }
        if let first = inBlock.map(\.memorizedAt).min(), let last = inBlock.map(\.memorizedAt).max() {
            recentBlock = RecentBlock(halves: inBlock.map(\.halfPage), firstLearned: first, lastLearned: last)
        } else {
            recentBlock = nil
        }
        recentReviewDoneToday = planReviews.contains { calendar.isDate($0.completedAt, inSameDayAs: now) }
        learnedToday = memorizedToday
        memorizedCount = memorized.count

        let firstLessonDay: Date?
        if case .due = lesson { firstLessonDay = today } else { firstLessonDay = plan.nextLessonDay(after: today, calendar: calendar) }
        projectedFinish = firstLessonDay.flatMap { plan.projectedFinish(remaining: remaining.count, from: $0, calendar: calendar) }

        var counts: [HalfPage: Int] = [:]
        for lesson in inBlock {
            counts[lesson.halfPage] = HifzGraduation.goodReviewDays(
                for: lesson, reviews: planReviews, before: now, calendar: calendar
            )
        }
        goodReviewsByHalf = counts
    }
}

/// What the plan will ask for on coming days, for reminders and the Revision Lock. Assumes each
/// lesson is done on its day and leaves out portions settling into revision, which only matters
/// in a plan's last days.
struct HifzForecast {
    let today: HifzToday
    let now: Date
    let calendar: Calendar

    init(today: HifzToday, now: Date = Date(), calendar: Calendar = .current) {
        self.today = today
        self.now = now
        self.calendar = calendar
    }

    private var plan: HifzPlan { today.plan }

    func lessonDue(on day: Date) -> Bool {
        guard plan.isActive else { return false }
        if calendar.isDate(day, inSameDayAs: now) { return today.isLessonDue }
        let remaining = today.totalCount - today.memorizedCount
        return plan.isLessonDay(day, calendar: calendar) && remaining - lessonsBefore(day) * plan.halvesPerDay > 0
    }

    func recentReviewDue(on day: Date) -> Bool {
        guard plan.isActive else { return false }
        if calendar.isDate(day, inSameDayAs: now) { return today.isRecentReviewDue }
        return today.recentBlock != nil || today.learnedToday || lessonsBefore(day) > 0
    }

    /// Due dates the Revision Lock can check without the app: one per item due today, or else
    /// one per item on the next day with anything due.
    func lockDueDates() -> [Date] {
        let start = calendar.startOfDay(for: now)
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { break }
            let count = (lessonDue(on: day) ? 1 : 0) + (recentReviewDue(on: day) ? 1 : 0)
            if count > 0 { return Array(repeating: day, count: count) }
        }
        return []
    }

    /// Lessons that will have been learned before `day`: today's if it's still to do, then one
    /// per lesson day in between.
    private func lessonsBefore(_ day: Date) -> Int {
        let target = calendar.startOfDay(for: day)
        var count = today.isLessonDue ? 1 : 0
        var current = calendar.startOfDay(for: now)
        while let next = calendar.date(byAdding: .day, value: 1, to: current), next < target {
            if plan.isLessonDay(next, calendar: calendar) { count += 1 }
            current = next
        }
        return count
    }
}

/// What a graduation pass moved into revision, for the notice on Home.
struct MovedToRevision: Equatable {
    let surahNames: [String]
    let frequency: Frequency

    var message: String {
        let names: String
        switch surahNames.count {
        case 0: names = "Your recent lessons"
        case 1: names = surahNames[0]
        case 2: names = "\(surahNames[0]) and \(surahNames[1])"
        default: names = "\(surahNames.dropLast().joined(separator: ", ")) and \(surahNames.last!)"
        }
        return "\(names) moved to revision, \(frequency.displayName.lowercased())."
    }
}

/// A change to a revision schedule when memorized pages move to revision.
struct RevisionChange: Equatable {
    enum Kind: Equatable {
        case create
        case extend(scheduleId: UUID)
    }

    let kind: Kind
    let surahId: Int
    /// Nil once the whole surah is covered.
    let pages: ClosedRange<Int>?

    var isFullSurah: Bool { pages == nil }
}

enum HifzGraduation {
    /// Days with a recent review rated Good or better, after the day the half was memorized and
    /// before `now`'s day. A review logged today counts from tomorrow, so undoing it never has
    /// to take anything back out of revision.
    static func goodReviewDays(for lesson: HifzLesson, reviews: [HifzReview], before now: Date, calendar: Calendar = .current) -> Int {
        let learned = calendar.startOfDay(for: lesson.memorizedAt)
        let today = calendar.startOfDay(for: now)
        let days = reviews
            .filter { $0.planId == lesson.planId && !$0.performanceRating.needsEarlierReview }
            .map { calendar.startOfDay(for: $0.completedAt) }
            .filter { $0 > learned && $0 < today }
        return Set(days).count
    }

    /// Halves still in recent review that have had enough good reviews to move to revision.
    static func halvesReady(lessons: [HifzLesson], reviews: [HifzReview], requiredCount: Int, now: Date, calendar: Calendar = .current) -> [HifzLesson] {
        lessons.filter {
            $0.graduatedAt == nil
                && goodReviewDays(for: $0, reviews: reviews, before: now, calendar: calendar) >= requiredCount
        }
    }

    /// How the plan's revision schedules change when `pages` move to revision.
    ///
    /// Each surah on each page gets its page added to the plan's schedule for that surah, or a new
    /// schedule if the plan has none yet. A surah is skipped where any other schedule already covers
    /// the page, so material the user was already revising isn't scheduled twice.
    static func revisionChanges(pages: [Int], planId: UUID, schedules: [ScheduleWithSurah], surahs: [Surah]) -> [RevisionChange] {
        var coverage: [Int: Coverage] = [:]
        var existingIds: [Int: UUID] = [:]
        var changed: [Int] = []

        for schedule in schedules where schedule.hifzPlanId == planId {
            let surahId = Int(schedule.surahId)
            existingIds[surahId] = schedule.id
            coverage[surahId] = schedule.pageRange.map(Coverage.pages) ?? .wholeSurah
        }

        for page in pages {
            for surah in QuranPages.surahs(onPage: page, in: surahs) {
                let coveredElsewhere = schedules.contains {
                    Int($0.surahId) == surah.id && $0.hifzPlanId != planId && $0.covers(page: page)
                }
                guard !coveredElsewhere else { continue }

                let widened: ClosedRange<Int>
                switch coverage[surah.id] {
                case .wholeSurah?:
                    continue
                case .pages(let range)? where range.contains(page):
                    continue
                case .pages(let range)?:
                    widened = min(range.lowerBound, page)...max(range.upperBound, page)
                case nil:
                    widened = page...page
                }
                let isWhole = widened.lowerBound <= surah.pageStart && widened.upperBound >= surah.pageEnd
                coverage[surah.id] = isWhole ? .wholeSurah : .pages(widened)
                if !changed.contains(surah.id) { changed.append(surah.id) }
            }
        }

        return changed.map { surahId in
            let kind: RevisionChange.Kind = existingIds[surahId].map { .extend(scheduleId: $0) } ?? .create
            if case .pages(let range)? = coverage[surahId] {
                return RevisionChange(kind: kind, surahId: surahId, pages: range)
            }
            return RevisionChange(kind: kind, surahId: surahId, pages: nil)
        }
    }

    private enum Coverage {
        case pages(ClosedRange<Int>)
        case wholeSurah
    }
}

extension ScheduleWithSurah {
    /// The pages a page-range schedule covers, or nil for a full surah.
    var pageRange: ClosedRange<Int>? {
        guard !isFullSurah, let startPage, let endPage else { return nil }
        return Int(min(startPage, endPage))...Int(max(startPage, endPage))
    }

    func covers(page: Int) -> Bool {
        guard let pageRange else { return true }
        return pageRange.contains(page)
    }
}

/// Ready-made plans offered when setting one up.
struct HifzPlanPreset: Identifiable, Equatable {
    let id: String
    let title: String
    let startPage: Int
    let endPage: Int

    static let all: [HifzPlanPreset] = [
        HifzPlanPreset(id: "juz30-back", title: "Juz 30 from An-Nas", startPage: 604, endPage: 582),
        HifzPlanPreset(id: "juz30", title: "Juz 30 from An-Naba", startPage: 582, endPage: 604),
        HifzPlanPreset(id: "juz29", title: "Juz 29 from Al-Mulk", startPage: 562, endPage: 581),
        HifzPlanPreset(id: "baqarah", title: "Whole Quran from Al-Baqarah", startPage: 2, endPage: 604),
    ]

    /// A custom plan between two surahs. When the first comes after the second it runs backward,
    /// from the end of the first surah to the start of the second.
    static func custom(from first: Surah, to last: Surah) -> HifzPlanPreset {
        let backward = first.id > last.id
        return HifzPlanPreset(
            id: "custom-\(first.id)-\(last.id)",
            title: first.id == last.id ? first.englishName : "\(first.englishName) to \(last.englishName)",
            startPage: backward ? first.pageEnd : first.pageStart,
            endPage: backward ? last.pageStart : last.pageEnd
        )
    }
}
