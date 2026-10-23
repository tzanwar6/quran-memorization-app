import Foundation

/// Page layout of the 604-page Madani mushaf that every page number in the app refers to.
enum QuranPages {
    static let count = 604

    /// The page each juz starts on. A juz that begins mid-page is counted from that page.
    static let juzStartPages = [
        1, 22, 42, 62, 82, 102, 121, 142, 162, 182,
        201, 222, 242, 262, 282, 302, 322, 342, 362, 382,
        402, 422, 442, 462, 482, 502, 522, 542, 562, 582,
    ]

    static func juz(forPage page: Int) -> Int {
        juzStartPages.lastIndex { $0 <= page }.map { $0 + 1 } ?? 1
    }

    static func pages(inJuz juz: Int) -> ClosedRange<Int> {
        let start = juzStartPages[juz - 1]
        let end = juz < juzStartPages.count ? juzStartPages[juz] - 1 : count
        return start...end
    }

    /// Surahs with any part on the page, in mushaf order. 51 pages hold more than one.
    static func surahs(onPage page: Int, in surahs: [Surah]) -> [Surah] {
        surahs.filter { $0.pageStart <= page && page <= $0.pageEnd }.sorted { $0.id < $1.id }
    }
}

/// How much of a page is memorized, for the progress map.
enum PageState: Hashable {
    case notStarted
    /// Some of the page is in revision, but not all of it: usually a page shared by several surahs.
    case partlyKnown
    /// Memorized through a plan and still in recent review.
    case learning
    case memorized
}

enum PageCoverage {
    /// One state per page; index 0 is page 1.
    ///
    /// A page is memorized when every surah on it has a revision schedule covering the page (active
    /// or paused), or when both its halves have moved to revision from a plan.
    static func compute(schedules: [ScheduleWithSurah], lessons: [HifzLesson], surahs: [Surah]) -> [PageState] {
        var surahsByPage = Array(repeating: [Int](), count: QuranPages.count + 1)
        for surah in surahs {
            for page in max(1, surah.pageStart)...min(QuranPages.count, surah.pageEnd) {
                surahsByPage[page].append(surah.id)
            }
        }

        var coveredSurahs = Array(repeating: Set<Int>(), count: QuranPages.count + 1)
        for schedule in schedules {
            let surahId = Int(schedule.surahId)
            guard let surah = surahs.first(where: { $0.id == surahId }) else { continue }
            let range: ClosedRange<Int>
            if !schedule.isFullSurah, let start = schedule.startPage, let end = schedule.endPage {
                range = Int(min(start, end))...Int(max(start, end))
            } else {
                range = surah.pageStart...surah.pageEnd
            }
            for page in range where (1...QuranPages.count).contains(page) {
                coveredSurahs[page].insert(surahId)
            }
        }

        var graduatedHalves = Array(repeating: 0, count: QuranPages.count + 1)
        var learningPages = Set<Int>()
        for lesson in lessons where (1...QuranPages.count).contains(lesson.halfPage.page) {
            if lesson.graduatedAt != nil {
                graduatedHalves[lesson.halfPage.page] += 1
            } else {
                learningPages.insert(lesson.halfPage.page)
            }
        }

        return (1...QuranPages.count).map { page in
            let onPage = Set(surahsByPage[page])
            let covered = coveredSurahs[page]
            if graduatedHalves[page] >= 2 || (!onPage.isEmpty && onPage.isSubset(of: covered)) {
                return .memorized
            }
            if learningPages.contains(page) { return .learning }
            if !covered.isEmpty || graduatedHalves[page] > 0 { return .partlyKnown }
            return .notStarted
        }
    }
}
