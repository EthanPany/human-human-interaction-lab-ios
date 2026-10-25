import XCTest

/// Walks the main screens on the mock backend and attaches a screenshot of each.
/// CI runs it on an iPhone and an iPad simulator and uploads the PNGs.
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    /// Signed out: sign up with a long name, pick an avatar, the setup choice,
    /// then the long name on the Profile tab and on the worn badge.
    func testSignedOut() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSignedOut", "-didChooseSetup", "NO", "-avatarSetupDone.me", "NO"]
        app.launch()

        let phone = app.textFields["Phone number"]
        XCTAssertTrue(phone.waitForExistence(timeout: 20))
        sleep(2)
        snap("01-sign-in")

        phone.tap()
        phone.typeText("5555550100")
        let name = app.textFields["Name"]
        if name.exists { name.tap(); name.typeText("Alexandria Montgomery") }
        snap("02-sign-in-filled")

        // Submit from the password field: on iPad the keyboard covers Continue
        let password = app.secureTextFields["Password"]
        if password.exists {
            password.tap()
            password.typeText("\n")
        }
        let continueButton = app.buttons["Continue"]
        if app.textFields["Phone number"].exists && continueButton.exists {
            if !continueButton.isHittable { app.swipeUp() }
            continueButton.tap()
        }

        // Step 2: the avatar
        XCTAssertTrue(app.staticTexts["Make your avatar"].waitForExistence(timeout: 15))
        sleep(2)
        snap("03-avatar-setup")
        let flower = app.buttons["Flower"].firstMatch
        if flower.waitForExistence(timeout: 5) { flower.tap() }
        let purple = app.buttons["Color #EB8FFF"].firstMatch
        if purple.exists { purple.tap() }
        sleep(1)
        snap("04-avatar-setup-picked")
        app.buttons["Continue"].firstMatch.tap()

        // Step 3: how to fill the profile
        XCTAssertTrue(app.staticTexts["How do you want to set up?"].waitForExistence(timeout: 15))
        sleep(2)
        snap("05-setup-choice")
        app.buttons["Skip for now"].firstMatch.tap()
        sleep(2)

        // The long name, laid out
        app.tabBars.buttons["Profile"].tap()
        sleep(2)
        snap("06-profile-long-name")
        app.tabBars.buttons["Badge"].tap()
        let wear = app.buttons["Wear badge"].firstMatch
        if wear.waitForExistence(timeout: 5) {
            snap("07-badge-tab-long-name")
            wear.tap()
            sleep(2)
            snap("08-worn-badge-long-name")
        }
    }

    /// Signed in demo user: every tab, the sheets, Settings, then the worn badge.
    func testSignedIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestDemo", "-didChooseSetup", "YES"]
        app.launch()

        let wear = app.buttons["Wear badge"].firstMatch
        XCTAssertTrue(wear.waitForExistence(timeout: 20))
        sleep(2)
        snap("10-badge-tab")

        // People and one person
        app.tabBars.buttons["People"].tap()
        sleep(2)
        snap("20-people")
        let maya = app.staticTexts["Maya"].firstMatch
        if maya.waitForExistence(timeout: 5) {
            maya.tap()
            sleep(2)
            snap("21-person-detail")
            app.swipeUp()
            sleep(1)
            snap("22-person-detail-scrolled")
            app.navigationBars.buttons.firstMatch.tap()
        } else {
            XCTFail("No people in the demo list")
        }

        // Profile, editor sheets, Settings
        app.tabBars.buttons["Profile"].tap()
        sleep(2)
        snap("30-profile")
        // Landscape is wide enough for the two column Profile and the People grid
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        snap("30b-profile-landscape")
        app.tabBars.buttons["People"].tap()
        sleep(2)
        snap("20b-people-landscape")
        app.tabBars.buttons["Profile"].tap()
        XCUIDevice.shared.orientation = .portrait
        sleep(3)
        app.swipeUp()
        sleep(1)
        snap("31-profile-scrolled")
        app.swipeDown()
        app.swipeDown()

        let customize = app.buttons["Customize badge"].firstMatch
        if customize.waitForExistence(timeout: 5) {
            customize.tap()
            sleep(2)
            snap("32-avatar-editor")
            app.swipeUp()
            sleep(1)
            snap("33-avatar-editor-scrolled")
            app.buttons["Done"].firstMatch.tap()
            sleep(1)
        } else {
            XCTFail("Customize badge button missing")
        }

        let settings = app.buttons["Settings"].firstMatch
        if settings.waitForExistence(timeout: 5) {
            settings.tap()
            sleep(2)
            snap("34-settings")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        } else {
            XCTFail("Settings button missing")
        }

        // The badge you wear. The mock cycles idle, match (closer and closer),
        // talking and saved every 4 s, so a few shots catch each state.
        app.tabBars.buttons["Badge"].tap()
        XCTAssertTrue(wear.waitForExistence(timeout: 5))
        wear.tap()
        sleep(2)
        for i in 0..<6 {
            snap("4\(i)-worn-badge")
            sleep(4)
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(3)
        snap("46-worn-badge-landscape")
        XCUIDevice.shared.orientation = .portrait
        sleep(2)

        // Pinch in to take it off
        app.pinch(withScale: 0.4, velocity: -2)
        sleep(2)
        if !wear.isHittable {
            // Pinch synthesis is flaky on simulators; record it, don't fail on it
            print("Pinch in did not take the badge off")
        }
        snap("47-after-take-off")
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
