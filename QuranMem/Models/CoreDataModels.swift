import CoreData

extension SurahEntity {
    func toStruct() -> Surah {
        Surah(
            id: Int(id),
            arabicName: arabicName ?? "",
            englishName: englishName ?? "",
            transliteration: transliteration ?? "",
            verseCount: Int(verseCount),
            pageStart: Int(pageStart),
            pageEnd: Int(pageEnd),
            revelation: revelation ?? ""
        )
    }
}

extension ScheduleEntity {
    func toScheduleWithSurah(surah: SurahEntity, hasBeenReviewed: Bool) -> ScheduleWithSurah {
        ScheduleWithSurah(
            id: id ?? UUID(),
            surahId: surahId,
            surahArabicName: surah.arabicName ?? "",
            surahEnglishName: surah.englishName ?? "",
            verseCount: surah.verseCount,
            frequency: Frequency(rawValue: frequency ?? "daily") ?? .daily,
            isFullSurah: isFullSurah,
            startPage: startPage == 0 ? nil : startPage,
            endPage: endPage == 0 ? nil : endPage,
            nextDueDate: nextDueDate ?? Date(),
            isActive: isActive,
            hasBeenReviewed: hasBeenReviewed,
            hifzPlanId: hifzPlanId
        )
    }
}

extension HifzPlanEntity {
    func toStruct() -> HifzPlan {
        HifzPlan(
            id: id ?? UUID(),
            title: title ?? "",
            startPage: Int(startPage),
            endPage: Int(endPage),
            halvesPerDay: Int(halvesPerDay),
            lessonWeekdays: lessonWeekdays,
            recentReviewCount: Int(recentReviewCount),
            revisionFrequency: Frequency(rawValue: revisionFrequency ?? "") ?? .weekly,
            isActive: isActive,
            completedAt: completedAt,
            createdAt: createdAt ?? Date()
        )
    }
}

extension HifzLessonEntity {
    func toStruct() -> HifzLesson {
        HifzLesson(
            id: id ?? UUID(),
            planId: planId ?? UUID(),
            halfPage: HalfPage(page: Int(page), half: HalfPage.Half(rawValue: half) ?? .top),
            memorizedAt: memorizedAt ?? Date(),
            notes: notes,
            graduatedAt: graduatedAt
        )
    }
}

extension HifzReviewEntity {
    func toStruct() -> HifzReview {
        HifzReview(
            id: id ?? UUID(),
            planId: planId ?? UUID(),
            completedAt: completedAt ?? Date(),
            performanceRating: PerformanceRating(rawValue: performanceRating ?? "good") ?? .good,
            notes: notes,
            firstPage: Int(firstPage),
            lastPage: Int(lastPage),
            halfCount: Int(halfCount)
        )
    }
}

extension SessionEntity {
    func toSessionWithSchedule(surah: SurahEntity, schedule: ScheduleEntity) -> SessionWithSchedule {
        SessionWithSchedule(
            id: id ?? UUID(),
            scheduleId: scheduleId ?? UUID(),
            surahArabicName: surah.arabicName ?? "",
            surahEnglishName: surah.englishName ?? "",
            performanceRating: PerformanceRating(rawValue: performanceRating ?? "good") ?? .good,
            completedAt: completedAt ?? Date(),
            notes: notes,
            frequency: Frequency(rawValue: schedule.frequency ?? "daily") ?? .daily
        )
    }
}

extension StatsEntity {
    func toStruct() -> UserStatistics {
        UserStatistics(
            currentStreak: Int(currentStreak),
            longestStreak: Int(longestStreak),
            totalSessions: Int(totalSessions),
            averageRating: averageRating,
            lastSessionDate: lastSessionDate
        )
    }
}
