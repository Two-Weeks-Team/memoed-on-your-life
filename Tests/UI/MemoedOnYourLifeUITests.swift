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

    func testEvidenceTabExplainsPermissionLightCapture() {
        let app = XCUIApplication()
        app.launchArguments = ["--evidence-tab"]
        app.launch()

        XCTAssertTrue(app.buttons["import-photo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["record-audio"].exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        attachScreenshot(of: app, named: "05-evidence-library")
    }

    func testPhysicalDeviceRecordsAndIndexesTimedSpeech() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Microphone capture requires a physical iPhone.")
#else
        let app = XCUIApplication()
        app.launchArguments = ["--evidence-tab"]
        app.launch()

        let audioRows = app.buttons.matching(identifier: "evidence-row-audio")
        let initialAudioRowCount = audioRows.count
        let recordAudio = app.buttons["record-audio"]
        XCTAssertTrue(recordAudio.waitForExistence(timeout: 10))
        recordAudio.tap()

        let operationTitle = app.staticTexts["library-operation-title"]
        XCTAssertTrue(operationTitle.waitForExistence(timeout: 5))
        XCTAssertTrue(operationTitle.label.contains("녹음 중"))
        attachScreenshot(of: app, named: "06-physical-recording")
        print("MEMOED_PHYSICAL_RECORDING_READY")

        Thread.sleep(forTimeInterval: 25)
        let stopRecording = app.buttons["record-audio"]
        XCTAssertTrue(stopRecording.waitForExistence(timeout: 5))
        stopRecording.tap()

        let newRowExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in audioRows.count > initialAudioRowCount },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [newRowExpectation], timeout: 180),
            .completed,
            "The recording should create a new durable audio evidence row."
        )

        let completed = NSPredicate { _, _ in
            operationTitle.exists && operationTitle.label.contains("완료")
        }
        let completedExpectation = XCTNSPredicateExpectation(
            predicate: completed,
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [completedExpectation], timeout: 180),
            .completed,
            "On-device speech indexing should reach the completed state."
        )

        audioRows.element(boundBy: 0).tap()
        let transcriptSpan = app.descendants(matching: .any)["audio-transcript-span"]
        XCTAssertTrue(
            transcriptSpan.waitForExistence(timeout: 10),
            "The physical recording should produce a finalized, time-indexed transcript span."
        )
        attachScreenshot(of: app, named: "07-physical-timed-transcript")
#endif
    }

    func testPhysicalDeviceRetainsTimedTranscriptAfterRelaunch() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("Physical persistence evidence is created by the microphone test.")
#else
        let app = XCUIApplication()
        app.launchArguments = ["--evidence-tab"]
        app.launch()

        let audioRow = app.buttons["evidence-row-audio"].firstMatch
        XCTAssertTrue(audioRow.waitForExistence(timeout: 10))
        audioRow.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["audio-transcript-span"]
                .waitForExistence(timeout: 10)
        )

        app.terminate()
        app.launch()

        let restoredAudioRow = app.buttons["evidence-row-audio"].firstMatch
        XCTAssertTrue(restoredAudioRow.waitForExistence(timeout: 10))
        restoredAudioRow.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["audio-transcript-span"]
                .waitForExistence(timeout: 10)
        )
        attachScreenshot(of: app, named: "08-physical-persisted-transcript")
#endif
    }

    private func attachScreenshot(of app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
