import XCTest

@MainActor
final class MemoedOnYourLifeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDemoShowsCurrentAnswerAndChallengeResult() {
        let app = XCUIApplication()
        app.launch()
        attachScreenshot(of: app, named: "01-home")

        let loadDemo = app.buttons["load-demo"]
        XCTAssertTrue(loadDemo.waitForExistence(timeout: 5))
        loadDemo.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["current-answer"].waitForExistence(timeout: 3)
        )
        attachScreenshot(of: app, named: "02-answer")

        let exactSource = app.buttons["source-corrected-invitation"]
        XCTAssertTrue(exactSource.waitForExistence(timeout: 3))
        exactSource.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["source-detail"].waitForExistence(timeout: 3)
        )
        attachScreenshot(of: app, named: "03-exact-source")

        let done = app.buttons["source-detail-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()

        let challenge = app.buttons["run-challenge"]
        XCTAssertTrue(challenge.waitForExistence(timeout: 3))
        challenge.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["challenge-result"].waitForExistence(timeout: 5)
        )
        attachScreenshot(of: app, named: "04-challenged")
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
