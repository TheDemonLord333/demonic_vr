//
//  Demonic_VRUITests.swift
//  Demonic VRUITests
//
//  Created by David Martens on 22.11.26.
//
//  Laufen ohne Netzwerk und ohne Google-Anmeldung: Mit "-DemonicUITest"
//  lädt die App keine YouTube-Seite und nutzt eine eigene UserDefaults-Suite.
//

import XCTest

final class Demonic_VRUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-DemonicUITest"]
        app.launch()
        return app
    }

    @MainActor
    func testStartScreenShowsAppName() throws {
        let app = launchApp()
        let title = app.staticTexts["app.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Demonic VR")
        XCTAssertTrue(app.textFields["link.field"].exists)
        XCTAssertTrue(app.buttons["nav.reference"].exists)
        XCTAssertTrue(app.buttons["nav.cardboard"].exists)
    }

    @MainActor
    func testReferenceSceneRunsInLandscapeAndReturnsToPlayer() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["nav.reference"].waitForExistence(timeout: 10))
        app.buttons["nav.reference"].tap()

        let counter = app.staticTexts["cardboard.frameCounter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10))

        // Framezähler läuft weiter (animierte Referenzszene).
        let first = counter.label
        let advanced = expectation(for: NSPredicate(format: "label != %@", first), evaluatedWith: counter)
        wait(for: [advanced], timeout: 5)

        // Querformat.
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(5)
        while window.frame.width <= window.frame.height && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertGreaterThan(window.frame.width, window.frame.height, "Cardboard muss im Querformat laufen")

        // Rückkehr zum Player.
        app.buttons["cardboard.exit"].tap()
        XCTAssertTrue(app.staticTexts["app.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["cardboard.frameCounter"].exists)
    }

    @MainActor
    func testCalibrationOpensAndResets() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["nav.calibration"].waitForExistence(timeout: 10))
        app.buttons["nav.calibration"].tap()

        let slider = app.sliders["calibration.screenScale"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        slider.adjust(toNormalizedSliderPosition: 0.2)

        let reset = app.buttons["calibration.reset"]
        if !reset.isHittable { app.swipeUp() }
        reset.tap()
        let confirm = app.buttons["Zurücksetzen"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertEqual(slider.value as? String, "90 %")

        app.buttons["sheet.done"].tap()
        XCTAssertTrue(app.staticTexts["app.title"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testInvalidLinkShowsWayBack() throws {
        let app = launchApp()
        let field = app.textFields["link.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("https://example.com/kein-video")
        app.buttons["link.open"].tap()

        XCTAssertTrue(app.buttons["issue.home"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["issue.dismiss"].exists)
        app.buttons["issue.dismiss"].tap()
        XCTAssertFalse(app.buttons["issue.home"].exists)
    }

    @MainActor
    func testReferenceDiagnosticsMeasuresFrames() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["nav.diagnostics"].waitForExistence(timeout: 10))
        app.buttons["nav.diagnostics"].tap()

        let referenceSegment = app.segmentedControls["diag.source"].buttons["Referenzszene"]
        XCTAssertTrue(referenceSegment.waitForExistence(timeout: 5))
        referenceSegment.tap()

        app.buttons["diag.live"].tap()
        XCTAssertTrue(app.images["diag.preview"].waitForExistence(timeout: 5))
        let motion = app.descendants(matching: .any).matching(identifier: "diag.motion").firstMatch
        let detected = expectation(for: NSPredicate(format: "label BEGINSWITH %@", "Bewegung"), evaluatedWith: motion)
        wait(for: [detected], timeout: 8)

        app.buttons["sheet.done"].tap()
    }

    @MainActor
    func testYouTubeCardboardIsBlockedWithoutSource() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["nav.cardboard"].waitForExistence(timeout: 10))
        app.buttons["nav.cardboard"].tap()
        let start = app.buttons["gate.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertFalse(start.isEnabled, "Ohne geladene YouTube-Quelle darf Cardboard nicht freigegeben werden")
        app.buttons["sheet.done"].tap()
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments += ["-DemonicUITest"]
            app.launch()
        }
    }
}
