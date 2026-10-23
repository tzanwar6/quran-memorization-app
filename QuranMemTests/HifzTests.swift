import CoreData
import Foundation
import Testing
@testable import QuranMem

private let calendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "UTC")!
    return value
}()
/// A Friday.
private let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 12))!
private func day(_ offset: Int, hour: Int = 12) -> Date {
    let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: today))!
    return calendar.date(byAdding: .hour, value: hour, to: start)!
}

private let surahs: [Surah] = {
    let url = Bundle.main.url(forResource: "surahs", withExtension: "json")!
    return try! JSONDecoder().decode([Surah].self, from: Data(contentsOf: url))
}()

private func plan(
    start: Int = 562, end: Int = 581, halvesPerDay: Int = 1,
    weekdays: Int16 = HifzPlan.allWeekdays, reviews: Int = 3, active: Bool = true
) -> HifzPlan {
    HifzPlan(
        id: UUID(), title: "Test", startPage: start, endPage: end, halvesPerDay: halvesPerDay,
        lessonWeekdays: weekdays, recentReviewCount: reviews, revisionFrequency: .weekly,
        isActive: active, completedAt: nil, createdAt: day(-30)
    )
}

private func lesson(_ plan: HifzPlan, _ page: Int, _ half: HalfPage.Half, on offset: Int, graduated: Bool = false) -> HifzLesson {
    HifzLesson(id: UUID(), planId: plan.id, halfPage: HalfPage(page: page, half: half), memorizedAt: day(offset), notes: nil, graduatedAt: graduated ? day(offset) : nil)
}

private func review(_ plan: HifzPlan, on offset: Int, _ rating: PerformanceRating = .good) -> HifzReview {
    HifzReview(id: UUID(), planId: plan.id, completedAt: day(offset), performanceRating: rating, notes: nil, firstPage: 562, lastPage: 562, halfCount: 1)
}

private func schedule(surah: Int, pages: ClosedRange<Int>? = nil, planId: UUID? = nil) -> ScheduleWithSurah {
    ScheduleWithSurah(
        id: UUID(), surahId: Int16(surah), surahArabicName: "", surahEnglishName: "", verseCount: 1,
        frequency: .weekly, isFullSurah: pages == nil,
        startPage: pages.map { Int16($0.lowerBound) }, endPage: pages.map { Int16($0.upperBound) },
        nextDueDate: day(3), isActive: true, hifzPlanId: planId
    )
}

// MARK: - Pages

struct QuranPagesTests {
    @Test func juzStartsMatchSurahsThatOpenAJuz() {
        // Juz that begin exactly where a surah begins.
        let openers = [14: 15, 15: 17, 17: 21, 18: 23, 26: 46, 28: 58, 29: 67, 30: 78]
        for (juz, surahId) in openers {
            let surah = surahs.first { $0.id == surahId }!
            #expect(QuranPages.juzStartPages[juz - 1] == surah.pageStart, "Juz \(juz)")
        }
        #expect(QuranPages.juzStartPages.count == 30)
        #expect(surahs.map(\.pageEnd).max() == QuranPages.count)
    }

    @Test func juzForPageAndPagesInJuz() {
        #expect(QuranPages.juz(forPage: 1) == 1)
        #expect(QuranPages.juz(forPage: 21) == 1)
        #expect(QuranPages.juz(forPage: 22) == 2)
        #expect(QuranPages.juz(forPage: 604) == 30)
        #expect(QuranPages.pages(inJuz: 30) == 582...604)
        #expect(QuranPages.pages(inJuz: 7) == 121...141)
    }

    @Test func sharedPagesListEverySurahOnThem() {
        #expect(QuranPages.surahs(onPage: 587, in: surahs).map(\.id) == [82, 83])
        // Juz 30 starts at the top of page 582, so Al-Mursalat ends on 581.
        #expect(QuranPages.surahs(onPage: 582, in: surahs).map(\.id) == [78])
        #expect(QuranPages.surahs(onPage: 604, in: surahs).map(\.id) == [112, 113, 114])
    }
}

// MARK: - Plan order and descriptions

struct HifzPlanTests {
    @Test func forwardPlanLearnsTopThenBottom() {
        let halves = plan(start: 562, end: 563).orderedHalves
        #expect(halves == [
            HalfPage(page: 562, half: .top), HalfPage(page: 562, half: .bottom),
            HalfPage(page: 563, half: .top), HalfPage(page: 563, half: .bottom),
        ])
    }

    @Test func backwardPlanStepsBackAPageButStillLearnsFromTheTop() {
        let backward = plan(start: 604, end: 603)
        #expect(backward.isBackward)
        #expect(backward.orderedHalves == [
            HalfPage(page: 604, half: .top), HalfPage(page: 604, half: .bottom),
            HalfPage(page: 603, half: .top), HalfPage(page: 603, half: .bottom),
        ])
        #expect(backward.totalHalves == 4)
        #expect(backward.pagesInOrder([603, 604, 603]) == [604, 603])
    }

    @Test func portionDescriptions() {
        let p = { (page: Int, half: HalfPage.Half) in HalfPage(page: page, half: half) }
        #expect([p(568, .top)].portionDescription == "Page 568 · top half")
        #expect([p(568, .top), p(568, .bottom)].portionDescription == "Page 568")
        #expect([p(568, .top), p(568, .bottom), p(569, .top), p(569, .bottom)].portionDescription == "Pages 568–569")
        #expect([p(568, .top), p(568, .bottom), p(569, .top)].portionDescription == "Page 568 + page 569 top half")
        #expect([p(568, .bottom), p(569, .top)].portionDescription == "Page 568 bottom half + page 569 top half")
    }

    @Test func weekdayDescriptions() {
        let allButFriday = HifzPlan.allWeekdays & ~Int16(1 << 5)
        #expect(HifzPlan.weekdaysDescription(HifzPlan.allWeekdays, calendar: calendar) == "Every day")
        #expect(HifzPlan.weekdaysDescription(allButFriday, calendar: calendar) == "Sat–Thu")
        #expect(HifzPlan.weekdaysDescription(0b010_1010, calendar: calendar) == "Mon, Wed, Fri")
    }

    @Test func projectedFinishSkipsRestDays() {
        let noFridays = plan(start: 562, end: 563, weekdays: HifzPlan.allWeekdays & ~Int16(1 << 5))
        // Four halves from a Friday: Sat, Sun, Mon, Tue.
        #expect(noFridays.projectedFinish(remaining: 4, from: day(0), calendar: calendar) == calendar.startOfDay(for: day(4)))
    }

    @Test func customRangeBetweenSurahs() {
        let mulk = surahs.first { $0.id == 67 }!
        let mursalat = surahs.first { $0.id == 77 }!
        let forward = HifzPlanPreset.custom(from: mulk, to: mursalat)
        #expect(forward.startPage == 562)
        #expect(forward.endPage == mursalat.pageEnd)
        let backward = HifzPlanPreset.custom(from: mursalat, to: mulk)
        #expect(backward.startPage == mursalat.pageEnd)
        #expect(backward.endPage == 562)
    }
}

// MARK: - Today

struct HifzTodayTests {
    private func todayFor(_ plan: HifzPlan, _ lessons: [HifzLesson] = [], _ reviews: [HifzReview] = []) -> HifzToday {
        HifzToday(plan: plan, lessons: lessons, reviews: reviews, now: today, calendar: calendar)
    }

    @Test func firstDayHasALessonAndNoRecentReview() {
        let state = todayFor(plan(halvesPerDay: 2))
        #expect(state.lesson == .due([HalfPage(page: 562, half: .top), HalfPage(page: 562, half: .bottom)]))
        #expect(state.recentBlock == nil)
        #expect(state.pendingCount == 1)
    }

    @Test func memorizingTodayMarksTheLessonDoneAndKeepsItOutOfTodaysRecentReview() {
        let p = plan()
        let state = todayFor(p, [lesson(p, 562, .top, on: -1), lesson(p, 562, .bottom, on: 0)])
        #expect(state.lesson == .done(next: [HalfPage(page: 563, half: .top)], nextDay: calendar.startOfDay(for: day(1))))
        #expect(state.recentBlock?.halves == [HalfPage(page: 562, half: .top)])
        #expect(state.isRecentReviewDue)
    }

    @Test func restDayStillHasRecentReview() {
        let p = plan(weekdays: HifzPlan.allWeekdays & ~Int16(1 << 5))
        let state = todayFor(p, [lesson(p, 562, .top, on: -1)])
        #expect(state.lesson == .restDay(next: [HalfPage(page: 562, half: .bottom)], nextDay: calendar.startOfDay(for: day(1))))
        #expect(state.pendingCount == 1)
    }

    @Test func finishedPlanHasNoLesson() {
        let p = plan(start: 562, end: 562)
        let state = todayFor(p, [lesson(p, 562, .top, on: -2, graduated: true), lesson(p, 562, .bottom, on: -1)])
        #expect(state.lesson == .finished)
        #expect(state.recentBlock?.halfCount == 1)
    }

    @Test func graduatedHalvesLeaveRecentReview() {
        let p = plan()
        let state = todayFor(p, [lesson(p, 562, .top, on: -5, graduated: true), lesson(p, 562, .bottom, on: -4)])
        #expect(state.recentBlock?.halves == [HalfPage(page: 562, half: .bottom)])
    }

    @Test func todaysReviewMarksRecentReviewDone() {
        let p = plan()
        let state = todayFor(p, [lesson(p, 562, .top, on: -1)], [review(p, on: 0)])
        #expect(state.recentReviewDoneToday)
        #expect(!state.isRecentReviewDue)
    }

    @Test func pausedPlanAsksForNothing() {
        let p = plan(active: false)
        let state = todayFor(p, [lesson(p, 562, .top, on: -1)])
        #expect(state.pendingCount == 0)
    }
}

// MARK: - Moving to revision

struct HifzGraduationTests {
    @Test func countsGoodReviewsAfterTheLessonDayAndBeforeToday() {
        let p = plan(reviews: 3)
        let half = lesson(p, 562, .top, on: -4)
        let reviews = [
            review(p, on: -4),          // the day it was memorized: doesn't count
            review(p, on: -3),
            review(p, on: -2, .poor),   // poor: doesn't count
            review(p, on: -1),
            review(p, on: -1),          // a second review the same day counts once
            review(p, on: 0),           // today: counts from tomorrow
        ]
        #expect(HifzGraduation.goodReviewDays(for: half, reviews: reviews, before: today, calendar: calendar) == 2)
        #expect(HifzGraduation.halvesReady(lessons: [half], reviews: reviews, requiredCount: 3, now: today, calendar: calendar).isEmpty)
        #expect(HifzGraduation.halvesReady(lessons: [half], reviews: reviews, requiredCount: 3, now: day(1), calendar: calendar).count == 1)
    }

    @Test func forwardThroughSharedPagesGrowsThenCompletesSurahs() {
        let id = UUID()
        // Page 591 holds all of At-Tariq and the start of Al-A'la (591–592).
        let first = HifzGraduation.revisionChanges(pages: [591], planId: id, schedules: [], surahs: surahs)
        #expect(first == [
            RevisionChange(kind: .create, surahId: 86, pages: nil),
            RevisionChange(kind: .create, surahId: 87, pages: 591...591),
        ])

        let existing = [schedule(surah: 87, pages: 591...591, planId: id)]
        let next = HifzGraduation.revisionChanges(pages: [592], planId: id, schedules: existing, surahs: surahs)
        #expect(next == [
            RevisionChange(kind: .extend(scheduleId: existing[0].id), surahId: 87, pages: nil),
            RevisionChange(kind: .create, surahId: 88, pages: nil),
        ])
    }

    @Test func backwardPlanWidensDownward() {
        let id = UUID()
        let existing = [schedule(surah: 83, pages: 588...589, planId: id)]
        let changes = HifzGraduation.revisionChanges(pages: [587], planId: id, schedules: existing, surahs: surahs)
        #expect(changes.contains(RevisionChange(kind: .extend(scheduleId: existing[0].id), surahId: 83, pages: nil)))
    }

    @Test func skipsWhatAnotherScheduleAlreadyCovers() {
        let id = UUID()
        let manual = [schedule(surah: 87)]
        let changes = HifzGraduation.revisionChanges(pages: [591, 592], planId: id, schedules: manual, surahs: surahs)
        #expect(!changes.contains { $0.surahId == 87 })
        #expect(changes.map(\.surahId) == [86, 88])
    }

    @Test func movedMessageListsNames() {
        #expect(MovedToRevision(surahNames: ["Al-Mulk"], frequency: .weekly).message == "Al-Mulk moved to revision, weekly.")
        #expect(MovedToRevision(surahNames: ["A", "B", "C"], frequency: .daily).message == "A, B and C moved to revision, daily.")
    }
}

// MARK: - Progress map

struct PageCoverageTests {
    @Test func sharedPageNeedsEverySurahOnIt() {
        let states = PageCoverage.compute(schedules: [schedule(surah: 82)], lessons: [], surahs: surahs)
        #expect(states[587 - 1] == .partlyKnown)
        #expect(states[1 - 1] == .notStarted)

        let all = PageCoverage.compute(schedules: [schedule(surah: 82), schedule(surah: 83)], lessons: [], surahs: surahs)
        #expect(all[587 - 1] == .memorized)
        #expect(all[588 - 1] == .memorized)
    }

    @Test func pageRangeSchedulesCoverOnlyTheirPages() {
        let states = PageCoverage.compute(schedules: [schedule(surah: 2, pages: 2...5)], lessons: [], surahs: surahs)
        #expect(states[2 - 1] == .memorized)
        #expect(states[5 - 1] == .memorized)
        #expect(states[6 - 1] == .notStarted)
    }

    @Test func lessonsShowAsLearningUntilBothHalvesMove() {
        let p = plan()
        let states = PageCoverage.compute(schedules: [], lessons: [
            lesson(p, 565, .top, on: -3),
            lesson(p, 566, .top, on: -9, graduated: true), lesson(p, 566, .bottom, on: -8, graduated: true),
            lesson(p, 567, .top, on: -9, graduated: true),
        ], surahs: surahs)
        #expect(states[565 - 1] == .learning)
        #expect(states[566 - 1] == .memorized)
        #expect(states[567 - 1] == .partlyKnown)
    }
}

// MARK: - Store

@MainActor
struct HifzDataStoreTests {
    private let store: DataStore

    init() {
        let context = PersistenceController(inMemory: true).container.viewContext
        store = DataStore(context: context, preferences: { .default })
    }

    private func makePlan(start: Int = 591, end: Int = 592, reviews: Int = 2, now: Date = Date()) async throws -> HifzPlan {
        try await store.createPlan(
            title: "Test", startPage: start, endPage: end, halvesPerDay: 2,
            lessonWeekdays: HifzPlan.allWeekdays, recentReviewCount: reviews, revisionFrequency: .weekly, now: now
        )
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    @Test func onlyOnePlanAtATime() async throws {
        _ = try await makePlan()
        await #expect(throws: DataStoreError.self) { _ = try await makePlan() }
    }

    @Test func memorizeAndUndo() async throws {
        let plan = try await makePlan()
        let ids = try await store.memorize([HalfPage(page: 591, half: .top), HalfPage(page: 591, half: .bottom)], planId: plan.id, notes: "Tricky start")
        #expect(ids.count == 2)
        #expect(try await store.getAllLessons().count == 2)
        #expect(try await store.getStats().currentStreak == 1)

        try await store.undoMemorize(lessonIds: ids)
        #expect(try await store.getAllLessons().isEmpty)
        #expect(try await store.getStats().currentStreak == 0)
    }

    @Test func recentReviewAndUndo() async throws {
        let plan = try await makePlan()
        let block = HifzToday.RecentBlock(halves: [HalfPage(page: 591, half: .top)], firstLearned: Date(), lastLearned: Date())
        let id = try await store.logRecentReview(planId: plan.id, block: block, performanceRating: .veryGood, notes: nil)
        #expect(try await store.getAllRecentReviews().count == 1)
        #expect(try await store.getStats().totalSessions == 1)

        try await store.deleteRecentReview(id: id)
        #expect(try await store.getAllRecentReviews().isEmpty)
    }

    @Test func goodRecentReviewsMoveCompletedPagesToRevision() async throws {
        let plan = try await makePlan(now: daysAgo(5))
        try await store.memorize([HalfPage(page: 591, half: .top), HalfPage(page: 591, half: .bottom)], planId: plan.id, notes: nil, now: daysAgo(4))
        let block = HifzToday.RecentBlock(halves: [HalfPage(page: 591, half: .top)], firstLearned: daysAgo(4), lastLearned: daysAgo(4))
        try await store.logRecentReview(planId: plan.id, block: block, performanceRating: .good, notes: nil, now: daysAgo(3))
        #expect(try await store.graduateReadyLessons() == nil)

        try await store.logRecentReview(planId: plan.id, block: block, performanceRating: .perfect, notes: nil, now: daysAgo(2))
        let moved = try await store.graduateReadyLessons()
        #expect(moved?.surahNames == ["At-Tariq", "Al-A'la"])

        let schedules = try await store.getAllSchedules()
        #expect(schedules.count == 2)
        #expect(schedules.allSatisfy { $0.hifzPlanId == plan.id && $0.frequency == .weekly })
        let ala = try #require(schedules.first { $0.surahId == 87 })
        #expect(!ala.isFullSurah)
        #expect(ala.startPage == 591 && ala.endPage == 591)
        #expect(!ala.isDueToday)
        #expect(schedules.first { $0.surahId == 86 }?.isFullSurah == true)
        #expect(try await store.getAllLessons().allSatisfy { $0.graduatedAt != nil })

        // A second pass has nothing left to move.
        #expect(try await store.graduateReadyLessons() == nil)
    }

    @Test func endingAPlanMovesEverythingMemorizedToRevision() async throws {
        let plan = try await makePlan()
        try await store.memorize([HalfPage(page: 591, half: .top)], planId: plan.id, notes: nil)
        let moved = try await store.endPlan(id: plan.id)
        #expect(moved?.surahNames == ["At-Tariq", "Al-A'la"])
        #expect(try await store.getCurrentPlan() == nil)
        #expect(try await store.getAllSchedules().count == 2)
    }

    @Test func resettingClearsPlans() async throws {
        let plan = try await makePlan()
        try await store.memorize([HalfPage(page: 591, half: .top)], planId: plan.id, notes: nil)
        try await store.clearAllData()
        #expect(try await store.getCurrentPlan() == nil)
        #expect(try await store.getAllLessons().isEmpty)
    }
}

// MARK: - Migration

@MainActor
struct ModelMigrationTests {
    /// A store created by the first model version must open with the current one, keeping its data.
    @Test func versionOneStoreMigrates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("QuranMem.sqlite")

        let v1URL = try #require(Bundle.main.url(forResource: "QuranMem", withExtension: "mom", subdirectory: "QuranMem.momd"))
        let v1 = try #require(NSManagedObjectModel(contentsOf: v1URL))
        #expect(v1.entitiesByName["HifzPlanEntity"] == nil)
        // Plain objects, so the old entities don't compete with the app's generated classes.
        v1.entities.forEach { $0.managedObjectClassName = NSStringFromClass(NSManagedObject.self) }

        let scheduleId = UUID()
        do {
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v1)
            let oldStore = try coordinator.addPersistentStore(type: .sqlite, at: url)
            let context = NSManagedObjectContext(.mainQueue)
            context.persistentStoreCoordinator = coordinator
            let schedule = NSEntityDescription.insertNewObject(forEntityName: "ScheduleEntity", into: context)
            schedule.setValue(scheduleId, forKey: "id")
            schedule.setValue(Int16(67), forKey: "surahId")
            schedule.setValue("weekly", forKey: "frequency")
            schedule.setValue(Date(), forKey: "nextDueDate")
            schedule.setValue(Date(), forKey: "createdAt")
            schedule.setValue(Date(), forKey: "updatedAt")
            let session = NSEntityDescription.insertNewObject(forEntityName: "SessionEntity", into: context)
            session.setValue(UUID(), forKey: "id")
            session.setValue(scheduleId, forKey: "scheduleId")
            session.setValue("good", forKey: "performanceRating")
            session.setValue(Date(), forKey: "completedAt")
            try context.save()
            try coordinator.remove(oldStore)
        }

        let migrated = PersistenceController(storeURL: url).container.viewContext
        let schedules = try migrated.fetch(ScheduleEntity.fetchRequest())
        #expect(schedules.map(\.id) == [scheduleId])
        #expect(schedules.first?.hifzPlanId == nil)
        #expect(try migrated.count(for: SessionEntity.fetchRequest()) == 1)
        #expect(try migrated.count(for: HifzPlanEntity.fetchRequest()) == 0)
    }
}

// MARK: - Reminders and lock

struct HifzForecastTests {
    private func forecast(_ plan: HifzPlan, _ lessons: [HifzLesson] = [], _ reviews: [HifzReview] = []) -> HifzForecast {
        HifzForecast(today: HifzToday(plan: plan, lessons: lessons, reviews: reviews, now: today, calendar: calendar), now: today, calendar: calendar)
    }

    @Test func todayFollowsWhatsStillToDo() {
        let p = plan()
        let f = forecast(p, [lesson(p, 562, .top, on: -1)])
        #expect(f.lessonDue(on: today))
        #expect(f.recentReviewDue(on: today))
        #expect(f.lockDueDates() == [calendar.startOfDay(for: today), calendar.startOfDay(for: today)])
    }

    @Test func doneTodayPointsTheLockAtTomorrow() {
        let p = plan()
        let f = forecast(p, [lesson(p, 562, .top, on: 0)])
        #expect(!f.lessonDue(on: today))
        #expect(!f.recentReviewDue(on: today))
        // Tomorrow brings the next lesson, and today's lesson joins recent review.
        #expect(f.lockDueDates() == Array(repeating: calendar.startOfDay(for: day(1)), count: 2))
    }

    @Test func restDaysHaveNoLesson() {
        let noSaturdays = plan(weekdays: HifzPlan.allWeekdays & ~Int16(1 << 6))
        let f = forecast(noSaturdays)
        #expect(!f.lessonDue(on: day(1)))
        #expect(f.recentReviewDue(on: day(1)))
        #expect(f.lessonDue(on: day(2)))
    }

    @Test func lessonsStopWhenThePlanRunsOut() {
        let short = plan(start: 562, end: 562)
        let f = forecast(short)
        #expect(f.lessonDue(on: today))
        #expect(f.lessonDue(on: day(1)))
        #expect(!f.lessonDue(on: day(2)))
    }

    @Test func pausedPlanForecastsNothing() {
        #expect(forecast(plan(active: false)).lockDueDates().isEmpty)
    }

    @Test func remindersIncludeTheLessonAndRecentReview() {
        let p = plan()
        let f = forecast(p, [lesson(p, 562, .top, on: -1)])
        let reminders = ReminderPlanner.plan(schedules: [], hifz: f, hour: 18, minute: 0, days: 1, now: today, calendar: calendar)
        #expect(reminders.count == 1)
        #expect(reminders[0].title == "🕌 Time to memorize")
        #expect(reminders[0].body == "Your new lesson and recent review are waiting.")
        #expect(reminders[0].badge == 2)
    }

    @Test func reminderBodiesCombineWithRevision() {
        #expect(ReminderPlanner.body(lesson: true, recentReview: false, revision: nil) == "Your new lesson is waiting.")
        #expect(ReminderPlanner.body(lesson: false, recentReview: true, revision: "Al-Mulk is due for review.") == "Recent review. Al-Mulk is due for review.")
        #expect(ReminderPlanner.body(lesson: false, recentReview: false, revision: "Al-Mulk is due for review.") == "Al-Mulk is due for review.")
    }
}

// MARK: - Home and Schedules

@MainActor
struct HifzHomeFlowTests {
    private let store: DataStore

    init() {
        store = DataStore(context: PersistenceController(inMemory: true).container.viewContext, preferences: { .default })
    }

    private func startPlan(_ home: HomeViewModel) async throws {
        try await home.createPlan(HifzPlanDraft(
            title: "Juz 30 from An-Naba", startPage: 582, endPage: 604, halvesPerDay: 1,
            lessonWeekdays: HifzPlan.allWeekdays, recentReviewCount: 14, revisionFrequency: .weekly
        ))
    }

    @Test func memorizingTodaysLessonCanBeUndone() async throws {
        let home = HomeViewModel(dataStore: store, isPlanHeldByLock: { _ in false })
        try await startPlan(home)
        let halves = try #require({ if case .due(let halves) = home.hifzToday?.lesson { return halves } else { return nil } }())
        #expect(halves == [HalfPage(page: 582, half: .top)])
        #expect(home.surahNames(onPages: [582]) == "An-Naba")

        try await home.memorize(halves, notes: nil)
        #expect(home.hifzToday?.memorizedCount == 1)
        guard case .lesson = home.lastCompleted else {
            Issue.record("Memorizing should be undoable")
            return
        }

        await home.undoLastSession()
        #expect(home.hifzToday?.memorizedCount == 0)
        #expect(home.lastCompleted == nil)
    }

    @Test func startingANextPlanEndsTheCurrentOne() async throws {
        let home = HomeViewModel(dataStore: store, isPlanHeldByLock: { _ in false })
        try await startPlan(home)
        try await home.memorize([HalfPage(page: 582, half: .top)], notes: nil)
        try await home.createPlan(HifzPlanDraft(
            title: "Juz 29 from Al-Mulk", startPage: 562, endPage: 581, halvesPerDay: 1,
            lessonWeekdays: HifzPlan.allWeekdays, recentReviewCount: 14, revisionFrequency: .weekly
        ), replacingCurrent: true)
        #expect(home.plan?.title == "Juz 29 from Al-Mulk")
        #expect(home.movedToRevision?.surahNames == ["An-Naba"])
    }

    @Test func permanentLockStopsEndingAPlanWithWorkDue() async throws {
        let home = HomeViewModel(dataStore: store, isPlanHeldByLock: { _ in true })
        try await startPlan(home)
        await #expect(throws: LockError.self) {
            try await home.createPlan(HifzPlanDraft(
                title: "Other", startPage: 1, endPage: 1, halvesPerDay: 1,
                lessonWeekdays: HifzPlan.allWeekdays, recentReviewCount: 7, revisionFrequency: .weekly
            ), replacingCurrent: true)
        }
        #expect(home.plan?.title == "Juz 30 from An-Naba")

        let schedules = SchedulesViewModel(dataStore: store, isHeldByLock: { _ in false }, isPlanHeldByLock: { _ in true })
        await schedules.loadData()
        await schedules.setPlanActive(false)
        #expect(schedules.lockNotice != nil)
        #expect(schedules.plan?.isActive == true)
        // Resuming tightens the lock, so it's always allowed; pausing is what's held.
        schedules.lockNotice = nil
        await schedules.endPlan()
        #expect(schedules.lockNotice != nil)
        #expect(schedules.plan != nil)
    }

    @Test func historyShowsLessonsAndRecentReviews() async throws {
        let home = HomeViewModel(dataStore: store, isPlanHeldByLock: { _ in false })
        try await startPlan(home)
        try await home.memorize([HalfPage(page: 582, half: .top)], notes: "Starts strong")
        let plan = try #require(home.plan)
        let block = HifzToday.RecentBlock(halves: [HalfPage(page: 582, half: .top)], firstLearned: Date(), lastLearned: Date())
        try await store.logRecentReview(planId: plan.id, block: block, performanceRating: .good, notes: nil)

        let progress = ProgressViewModel(dataStore: store)
        await progress.loadData()
        let items = progress.historyGroupedByDate.flatMap(\.1)
        #expect(items.count == 2)
        #expect(progress.ratedSessions.count == 1)
        #expect(progress.ratedSessions.first?.surahEnglishName == "Page 582 · 1 half page")
        #expect(progress.pageStates[582 - 1] == .learning)
    }
}
