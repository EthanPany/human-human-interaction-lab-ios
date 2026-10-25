import XCTest

/// Slow, demo friendly walks through the app on the mock backend, recorded
/// with `xcrun simctl io recordVideo` for the demo video. Each test is one
/// clip. `-demoReel` (debug builds only) scripts the approach, fakes the
/// recording meter and adds people to the list. Not run in CI.
final class DemoReelTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ extra: [String] = [], approachDelay: Int = 9999) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestDemo", "-demoReel", "-didChooseSetup", "YES",
                               "-demoApproachDelay", "\(approachDelay)"] + extra
        app.launch()
        return app
    }

    private func pause(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    /// A slow finger drag from one point of the screen to another (fractions).
    private func drag(_ app: XCUIApplication, from: CGVector, to: CGVector) {
        let a = app.coordinate(withNormalizedOffset: from)
        let b = app.coordinate(withNormalizedOffset: to)
        a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    /// rec08: sign in, then the avatar step.
    func testRec08SignIn() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestSignedOut", "-didChooseSetup", "NO", "-avatarSetupDone.me", "NO"]
        app.launch()
        let phone = app.textFields["Phone number"]
        XCTAssertTrue(phone.waitForExistence(timeout: 20))
        pause(2)
        let name = app.textFields["Name"]
        if name.exists { name.tap(); name.typeText("Ethan") }
        phone.tap()
        phone.typeText("5555550100")
        pause(1)
        let next = app.buttons["Next"].firstMatch
        if next.exists {
            next.tap()
            app.typeText("\n")
        } else {
            let password = app.secureTextFields["Password"]
            password.tap()
            password.typeText("\n")
        }
        XCTAssertTrue(app.staticTexts["Make your avatar"].waitForExistence(timeout: 15))
        pause(2)
        let flower = app.buttons["Flower"].firstMatch
        if flower.waitForExistence(timeout: 5) { flower.tap() }
        pause(1.2)
        let purple = app.buttons["Color #EB8FFF"].firstMatch
        if purple.exists { purple.tap() }
        pause(2.5)
    }

    /// rec09: the Badge tab, then putting the badge on (swipe up), idle.
    func testRec09Badge() {
        let app = launch()
        let wear = app.buttons["Wear badge"].firstMatch
        XCTAssertTrue(wear.waitForExistence(timeout: 20))
        pause(3)
        drag(app, from: CGVector(dx: 0.5, dy: 0.62), to: CGVector(dx: 0.5, dy: 0.25))
        pause(1)
        if wear.isHittable { wear.tap() }
        pause(5)
    }

    /// rec10 + rec13: the People list, Maya's card, scrolled to the summary and follow up.
    func testRec10People() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["People"].waitForExistence(timeout: 20))
        pause(1.5)
        app.tabBars.buttons["People"].tap()
        pause(2.5)
        let maya = app.staticTexts["Maya"].firstMatch
        XCTAssertTrue(maya.waitForExistence(timeout: 5))
        maya.tap()
        pause(3)
        drag(app, from: CGVector(dx: 0.5, dy: 0.75), to: CGVector(dx: 0.5, dy: 0.45))
        pause(2.5)
        drag(app, from: CGVector(dx: 0.5, dy: 0.75), to: CGVector(dx: 0.5, dy: 0.45))
        pause(3)
    }

    /// rec14: the People list scrolling slowly.
    func testRec14PeopleList() {
        let app = launch()
        XCTAssertTrue(app.tabBars.buttons["People"].waitForExistence(timeout: 20))
        app.tabBars.buttons["People"].tap()
        pause(2.5)
        drag(app, from: CGVector(dx: 0.5, dy: 0.78), to: CGVector(dx: 0.5, dy: 0.4))
        pause(1.5)
        drag(app, from: CGVector(dx: 0.5, dy: 0.78), to: CGVector(dx: 0.5, dy: 0.4))
        pause(1.5)
        drag(app, from: CGVector(dx: 0.5, dy: 0.3), to: CGVector(dx: 0.5, dy: 0.85))
        pause(2)
    }

    /// rec11 + rec12: worn badge, idle, Maya approaches (tint grows, topics
    /// flip), then the meet moment and the recording pill.
    func testRec11Approach() {
        let app = launch(approachDelay: 7)
        let wear = app.buttons["Wear badge"].firstMatch
        XCTAssertTrue(wear.waitForExistence(timeout: 20))
        wear.tap()
        pause(38)
    }
}
