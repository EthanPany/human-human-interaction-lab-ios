import XCTest

/// Group encounters on the mock backend: the group row in People, the group's
/// page, the group line on a member's page, and the worn badge while Maya,
/// Leo and Sam join (the mock cycles: Maya, then Leo, then Sam, 4 s apart).
final class GroupScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    func testGroupScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestDemo", "-didChooseSetup", "YES"]
        app.launch()
        let wear = app.buttons["Wear badge"].firstMatch
        XCTAssertTrue(wear.waitForExistence(timeout: 20))

        app.tabBars.buttons["People"].tap()
        sleep(2)
        snap("60-people-with-group")
        let row = app.staticTexts["Maya and Daniel"].firstMatch
        if row.waitForExistence(timeout: 5) {
            row.tap()
            sleep(2)
            snap("61-group-detail")
            app.swipeUp()
            sleep(1)
            snap("62-group-detail-scrolled")
            let maya = app.buttons.containing(.staticText, identifier: "Maya").firstMatch
            if maya.exists {
                maya.tap()
                sleep(2)
                app.swipeUp()
                sleep(1)
                snap("63-person-with-group-encounter")
            }
            app.navigationBars.buttons.firstMatch.tap()
        } else {
            XCTFail("No group row in People")
        }

        // The worn badge: catch the pair, then the group of three and four
        app.tabBars.buttons["Badge"].tap()
        XCTAssertTrue(wear.waitForExistence(timeout: 5))
        wear.tap()
        sleep(1)
        for i in 0..<9 {
            snap("6\(4 + i / 5)\(i % 5)-worn-badge-group")
            sleep(4)
        }
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
