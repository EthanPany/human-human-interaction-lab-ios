import XCTest

/// Phase 5 screens on the mock backend: share requests, a person's contact
/// info, the People filters, What I share, About and the profile photo.
final class SharingScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func testSharingScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestDemo", "-didChooseSetup", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["Wear badge"].firstMatch.waitForExistence(timeout: 20))

        // People: Daniel's offer waits on top
        app.tabBars.buttons["People"].tap()
        sleep(2)
        snap("50-people-with-request")
        XCTAssertTrue(app.staticTexts["Daniel Okafor wants to share their info"].firstMatch.waitForExistence(timeout: 5),
                      "Approval card missing")

        let filter = app.buttons["Filter and group"].firstMatch
        if filter.waitForExistence(timeout: 5) {
            filter.tap()
            sleep(1)
            snap("51-people-filter-menu")
            let matches = app.buttons["Matches"].firstMatch
            if matches.exists { matches.tap() } else { app.tap() }
            sleep(1)
            snap("52-people-matches-only")
            if filter.exists {
                filter.tap()
                let clear = app.buttons["Clear filters"].firstMatch
                if clear.waitForExistence(timeout: 2) { clear.tap() } else { app.tap() }
            }
        }

        let search = app.searchFields.firstMatch
        if search.waitForExistence(timeout: 3) {
            search.tap()
            search.typeText("Hiring")
            sleep(1)
            snap("53-people-search-topic")
            let cancel = app.buttons["Cancel"].firstMatch
            if cancel.exists { cancel.tap() }
        }

        // Maya shares her info with me
        let maya = app.staticTexts["Maya"].firstMatch
        if maya.waitForExistence(timeout: 5) {
            maya.tap()
            sleep(2)
            for _ in 0..<2 where !app.staticTexts["Contact info"].firstMatch.isHittable { app.swipeUp() }
            sleep(1)
            snap("54-person-contact-info")
            let share = app.buttons["Share my info"].firstMatch
            if share.waitForExistence(timeout: 3) {
                share.tap()
                sleep(1)
                snap("55-share-pick-sheet")
                app.buttons["Cancel"].firstMatch.tap()
                sleep(1)
            }
            app.navigationBars.buttons.firstMatch.tap()
        }

        // Profile: photo in the editor, then Settings > What I share and About
        app.tabBars.buttons["Profile"].tap()
        sleep(2)
        let editPhoto = app.buttons["Edit profile and photo"].firstMatch
        if editPhoto.waitForExistence(timeout: 5) {
            editPhoto.tap()
            sleep(2)
            snap("56-profile-photo-editor")
            app.buttons["Cancel"].firstMatch.tap()
            sleep(1)
        }
        let settings = app.buttons["Settings"].firstMatch
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
            sleep(1)
            let whatIShare = app.buttons["What I share"].firstMatch
            if whatIShare.waitForExistence(timeout: 5) {
                whatIShare.tap()
                sleep(1)
                snap("57-what-i-share")
                app.navigationBars.buttons.firstMatch.tap()
                sleep(1)
            }
            for _ in 0..<8 { app.swipeUp() }
            sleep(1)
            snap("58-settings-about")
        }
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
