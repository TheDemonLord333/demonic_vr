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

    /// - Parameter devOptions: Entwickleroptionen auf der Hauptseite zeigen (für Tests der Entwicklerfunktionen).
    @MainActor
    private func launchApp(devOptions: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-DemonicUITest"]
        if devOptions { app.launchArguments += ["-DemonicDevOptions"] }
        app.launch()
        return app
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        app.buttons["menu.more"].tap()
        let item = app.buttons["Einstellungen"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertTrue(app.switches["settings.devOptions"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStartScreenShowsAppName() throws {
        let app = launchApp(devOptions: false)
        let title = app.staticTexts["app.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Demonic VR")
        // Normale Bedienung direkt erreichbar.
        XCTAssertTrue(app.buttons["vr.start"].exists)
        XCTAssertTrue(app.textFields["link.field"].exists)
        XCTAssertTrue(app.buttons["link.open"].exists)
        XCTAssertTrue(app.buttons["nav.home"].exists)
        XCTAssertTrue(app.buttons["nav.back"].exists)
        XCTAssertTrue(app.buttons["nav.playlists"].exists)
        // Entwicklerfunktionen standardmäßig ausgeblendet.
        XCTAssertFalse(app.buttons["nav.reference"].exists)
        XCTAssertFalse(app.buttons["nav.mirrorTest"].exists)
        XCTAssertFalse(app.buttons["nav.diagnostics"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["developer.statusBar"].exists)
    }

    @MainActor
    func testSettingsToggleDeveloperOptionsRepeatedly() throws {
        let app = launchApp(devOptions: false)
        XCTAssertTrue(app.buttons["menu.more"].waitForExistence(timeout: 10))
        for expectVisible in [true, false, true] {
            openSettings(app)
            app.switches["settings.devOptions"].tap()
            app.buttons["sheet.done"].tap()
            XCTAssertTrue(app.staticTexts["app.title"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["nav.reference"].waitForExistence(timeout: 2), expectVisible)
            XCTAssertEqual(app.descendants(matching: .any)["developer.statusBar"].exists, expectVisible)
        }
        // Kalibrierung ist als normale Einstellung erreichbar.
        openSettings(app)
        app.buttons["settings.calibration"].tap()
        XCTAssertTrue(app.sliders["calibration.screenScale"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testVRButtonWithoutVideoExplainsWhy() throws {
        let app = launchApp(devOptions: false)
        XCTAssertTrue(app.buttons["vr.start"].waitForExistence(timeout: 10))
        app.buttons["vr.start"].tap()
        XCTAssertTrue(app.buttons["issue.dismiss"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["cardboard.exit"].exists)
        app.buttons["issue.dismiss"].tap()
    }

    @MainActor
    func testVRStartsTwoReplicasAndSwitchesBackRepeatedly() throws {
        let app = launchApp(devOptions: false)
        XCTAssertTrue(app.buttons["menu.more"].waitForExistence(timeout: 10))
        openSettings(app)
        app.buttons["Lokales Testvideo laden"].tap()

        for round in 1...3 {
            // Warten, bis das Testvideo erkannt ist; vorher erklärt ein Hinweis den Grund.
            var started = false
            for _ in 0..<15 where !started {
                app.buttons["vr.start"].tap()
                started = app.buttons["cardboard.exit"].waitForExistence(timeout: 2)
                if !started, app.buttons["issue.dismiss"].exists { app.buttons["issue.dismiss"].tap() }
            }
            XCTAssertTrue(started, "VR startet nicht (Runde \(round))")
            XCTAssertTrue(app.staticTexts["VR · Testvideo"].exists)
            // Testhilfen sind im normalen VR-Modus ausgeblendet.
            XCTAssertFalse(app.staticTexts["cardboard.half.left"].exists)
            XCTAssertTrue(app.buttons["cardboard.stop"].exists)
            app.buttons["cardboard.exit"].tap()
            XCTAssertTrue(app.buttons["vr.start"].waitForExistence(timeout: 5))

            // Einstellungen während der Wiedergabe öffnen und schließen.
            openSettings(app)
            app.buttons["sheet.done"].tap()
        }
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
    func testLocalVideoMirrorRunLabelsHalvesAndReports() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["nav.mirrorTest"].waitForExistence(timeout: 10))
        app.buttons["nav.mirrorTest"].tap()

        app.buttons["mirror.loadLocal"].tap()
        let start = app.buttons["mirror.startLocal"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: start)
        wait(for: [enabled], timeout: 20)
        start.tap()

        let left = app.staticTexts["cardboard.half.left"]
        XCTAssertTrue(left.waitForExistence(timeout: 10))
        XCTAssertTrue(left.label.contains("LINKE HÄLFTE"))
        XCTAssertTrue(left.label.contains("Original-WebView"))
        XCTAssertTrue(app.staticTexts["cardboard.half.right"].label.contains("Replikat"))

        // Brillentaste/Play-Pause: Rückmeldung erscheint.
        app.buttons["cardboard.playPause"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["cardboard.playbackFeedback"].waitForExistence(timeout: 3))

        app.buttons["cardboard.exit"].tap()
        XCTAssertTrue(app.staticTexts["app.title"].waitForExistence(timeout: 5))

        app.buttons["nav.mirrorTest"].tap()
        let report = app.staticTexts["mirror.report"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        XCTAssertTrue(report.label.contains("Lokales Testvideo"))
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
