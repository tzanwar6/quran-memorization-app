import XCTest

final class DailyReviewFlowUITests: XCTestCase {
    @MainActor
    func testFirstScheduleQueueResumeCompletionAndQuickLog() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-remindersEnabled", "NO"]
        app.launch()

        XCTAssertTrue(app.buttons["Choose Your First Surah"].waitForExistence(timeout: 10))
        capture(app, "01-first-use")
        app.buttons["Choose Your First Surah"].tap()
        createSchedule(app, named: "Al-Fatiha")
        XCTAssertTrue(app.staticTexts["0 of 1 reviews complete"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Schedules"].tap()
        app.buttons["New Schedule"].tap()
        createSchedule(app, named: "Al-Baqarah")
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["0 of 2 reviews complete"].waitForExistence(timeout: 5))
        capture(app, "02-daily-summary")
        app.buttons["startReview"].tap()
        XCTAssertTrue(app.staticTexts["Review 1 of 2"].waitForExistence(timeout: 5))
        capture(app, "03-passage")
        app.buttons["I’ve Finished Reciting"].tap()
        app.buttons["Good, 3 of 5. Some hesitation"].tap()
        capture(app, "04-rating")
        app.buttons["Save & Next"].tap()
        XCTAssertTrue(app.staticTexts["Review 2 of 2"].waitForExistence(timeout: 5))
        app.buttons["End Review"].tap()
        XCTAssertTrue(app.staticTexts["1 of 2 reviews complete"].waitForExistence(timeout: 5))

        app.buttons["startReview"].tap()
        XCTAssertTrue(app.staticTexts["Review 1 of 1"].waitForExistence(timeout: 5))
        app.buttons["Already reviewed? Log it now"].tap()
        app.buttons["Very Good, 4 of 5. Minor mistakes"].tap()
        app.buttons["Finish Reviews"].tap()
        XCTAssertTrue(app.staticTexts["You’ve finished your reviews"].waitForExistence(timeout: 5))
        capture(app, "05-queue-complete")
        app.buttons["Back to Today"].tap()
        XCTAssertTrue(app.staticTexts["Today’s Reviews Are Complete"].waitForExistence(timeout: 5))
        capture(app, "06-day-complete")

        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts["1 of 2 reviews complete"].waitForExistence(timeout: 5))
        // The due card still opens the short logging path directly.
        app.buttons.containing(.staticText, identifier: "Al-Baqarah").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Log Review"].waitForExistence(timeout: 5))
        app.buttons["Perfect, 5 of 5. Flawless recitation"].tap()
        app.buttons["Save Review"].tap()
        XCTAssertTrue(app.staticTexts["Today’s Reviews Are Complete"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLargeTextDarkModeReviewControlsRemainReachable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-remindersEnabled", "NO", "-colorScheme", "dark",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Choose Your First Surah"].waitForExistence(timeout: 10))
        app.buttons["Choose Your First Surah"].tap()
        createSchedule(app, named: "Al-Fatiha")
        XCTAssertTrue(app.buttons["startReview"].waitForExistence(timeout: 5))
        capture(app, "07-large-text-dark-home")
        app.buttons["startReview"].tap()
        XCTAssertTrue(app.buttons["I’ve Finished Reciting"].waitForExistence(timeout: 5))
        capture(app, "08-large-text-dark-passage")
        app.buttons["I’ve Finished Reciting"].tap()
        app.buttons["Perfect, 5 of 5. Flawless recitation"].tap()
        capture(app, "09-large-text-dark-rating")
        app.buttons["Finish Reviews"].tap()
        XCTAssertTrue(app.buttons["Back to Today"].waitForExistence(timeout: 5))
        app.buttons["Back to Today"].tap()
        XCTAssertTrue(app.staticTexts["Today’s Reviews Are Complete"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func createSchedule(_ app: XCUIApplication, named name: String) {
        let cell = app.cells.containing(.staticText, identifier: name).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        let create = app.buttons["Create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
