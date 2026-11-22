//
//  Demonic_VRTests.swift
//  Demonic VRTests
//
//  Created by David Martens on 22.11.26.
//

import CoreGraphics
import Foundation
import QuartzCore
import Testing
import UIKit
@testable import Demonic_VR

// MARK: - YouTube-Links

@MainActor
struct YouTubeLinkTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ&feature=share",
        "youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?si=abc",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ",
        "dQw4w9WgXcQ",
        "Schau mal: https://youtu.be/dQw4w9WgXcQ !",
    ])
    func recognizesVideoLinks(_ input: String) {
        #expect(YouTubeLink.parse(input)?.videoID == "dQw4w9WgXcQ")
    }

    @Test func readsStartTime() {
        #expect(YouTubeLink.parse("https://youtu.be/dQw4w9WgXcQ?t=90") == .video(id: "dQw4w9WgXcQ", start: 90))
        #expect(YouTubeLink.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=1m30s") == .video(id: "dQw4w9WgXcQ", start: 90))
        #expect(YouTubeLink.parseTime("1h2m3s") == 3723)
        #expect(YouTubeLink.parseTime("abc") == nil)
        #expect(YouTubeLink.parseTime("5x") == nil)
    }

    @Test func recognizesPlaylistsAndPages() {
        #expect(YouTubeLink.parse("https://www.youtube.com/playlist?list=PLabcdefgh123") == .playlist(id: "PLabcdefgh123"))
        let channel = YouTubeLink.parse("https://www.youtube.com/@SomeChannel")
        #expect(channel?.siteURL.host == "m.youtube.com")
        #expect(channel?.siteURL.path == "/@SomeChannel")
    }

    @Test(arguments: [
        "",
        "   ",
        "https://example.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/kurz",
        "https://www.youtube.com/watch?v=zu_kurz",
        "irgendein Text",
        "ftp://youtube.com/watch?v=dQw4w9WgXcQ",
    ])
    func rejectsInvalidLinks(_ input: String) {
        #expect(YouTubeLink.parse(input) == nil)
    }

    @Test func buildsMobileWatchURL() {
        let url = YouTubeLink.video(id: "dQw4w9WgXcQ", start: 42).siteURL
        #expect(url.absoluteString == "https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=42s")
    }

    @Test func invalidLinkProducesRecoveryIssue() {
        let player = PlayerController(startURL: nil)
        #expect(player.open(input: "https://example.com") == false)
        let actions = player.issue?.actions ?? []
        #expect(actions.contains(.goHome))
        #expect(actions.contains(.dismiss))
        player.perform(.dismiss)
        #expect(player.issue == nil)
    }

    @Test func embedErrorsOfferWayBack() {
        let issue = PlayerController.embedIssue(code: 150, videoID: "dQw4w9WgXcQ")
        #expect(issue.actions.first == .openOnYouTube(YouTubeLink.video(id: "dQw4w9WgXcQ", start: nil).siteURL))
        #expect(issue.actions.contains(.goHome))
    }

    @Test func classifiesPages() {
        #expect(PlayerController.classify(URL(string: "https://m.youtube.com/watch?v=x"), embedVideoID: nil) == .youtubeSite)
        #expect(PlayerController.classify(URL(string: "about:blank"), embedVideoID: nil) == .blank)
        #expect(PlayerController.classify(PlayerController.embedOrigin, embedVideoID: "dQw4w9WgXcQ") == .embed(videoID: "dQw4w9WgXcQ"))
        #expect(PlayerController.classify(URL(string: "https://example.com"), embedVideoID: nil) == .other)
    }

    @Test func embedPageUsesDocumentedPlayerAndKeepsControls() {
        let html = EmbedPlayerPage.html(videoID: "dQw4w9WgXcQ", start: 5, origin: PlayerController.embedOrigin)
        #expect(html.contains("https://www.youtube.com/iframe_api"))
        #expect(html.contains("playsinline: 1"))
        #expect(html.contains("\"dQw4w9WgXcQ\""))
        #expect(!html.contains("controls: 0"))
    }
}

// MARK: - Eine WebView

@MainActor
struct SingleWebViewTests {
    @Test func playerKeepsOneWebViewInstance() {
        let model = AppModel(environment: AppEnvironment(isUITest: true))
        // Die WebView entsteht erst beim ersten Anzeigen, nicht schon mit dem Modell.
        #expect(model.player.webView == nil)
        let webView = model.player.hostedWebView()
        #expect(model.player.hostedWebView() === webView)
        let before = model.player.continuityMark()
        model.startReferenceCardboard()
        #expect(model.isInCardboard)
        model.exitCardboard()
        let after = model.player.continuityMark()
        #expect(before.webViewID == ObjectIdentifier(webView))
        #expect(after.webViewID == ObjectIdentifier(webView))
        #expect(ContinuityReport(before: before, after: after).sameWebView)
    }

    @Test func continuityDetectsPositionReset() {
        let id = ObjectIdentifier(NSObject())
        let url = URL(string: "https://m.youtube.com/watch?v=dQw4w9WgXcQ")
        let before = ContinuityMark(webViewID: id, url: url, currentTime: 120, isPaused: false, hasVideo: true, date: Date())
        let ok = ContinuityMark(webViewID: id, url: url, currentTime: 125, isPaused: false, hasVideo: true, date: Date())
        let reset = ContinuityMark(webViewID: id, url: url, currentTime: 0, isPaused: true, hasVideo: true, date: Date())
        #expect(ContinuityReport(before: before, after: ok).isContinuous)
        #expect(!ContinuityReport(before: before, after: reset).positionPreserved)
    }
}

// MARK: - Stereo-Layout

@MainActor
struct StereoLayoutTests {
    let screen = CGSize(width: 874, height: 402) // iPhone 17 Pro, Querformat (Punkte)

    @Test func bothEyesGetIdenticalScreensWithCorrectAspect() {
        let layout = StereoLayout.compute(container: screen, contentAspect: 16.0 / 9.0, settings: .default)
        #expect(layout.leftScreen.size == layout.rightScreen.size)
        #expect(abs(layout.leftScreen.width / layout.leftScreen.height - 16.0 / 9.0) < 0.001)
        #expect(layout.leftEye.contains(layout.leftScreen))
        #expect(layout.rightEye.contains(layout.rightScreen))
    }

    @Test func screensAreSymmetricAroundCenter() {
        var settings = CalibrationSettings.default
        settings.horizontalSpacing = 0.12
        let layout = StereoLayout.compute(container: screen, contentAspect: 2.39, settings: settings)
        let center = screen.width / 2
        #expect(abs((center - layout.leftScreen.midX) - (layout.rightScreen.midX - center)) < 0.001)
        #expect(layout.leftScreen.midY == layout.rightScreen.midY)
    }

    @Test func spacingAndVerticalOffsetMoveScreens() {
        let base = StereoLayout.compute(container: screen, contentAspect: 16.0 / 9.0, settings: .default)
        var settings = CalibrationSettings.default
        settings.horizontalSpacing = 0.1
        settings.verticalOffset = 0.2
        let moved = StereoLayout.compute(container: screen, contentAspect: 16.0 / 9.0, settings: settings)
        #expect(moved.rightScreen.midX - moved.leftScreen.midX > base.rightScreen.midX - base.leftScreen.midX)
        #expect(moved.leftScreen.midY > base.leftScreen.midY)
    }

    @Test func tallContentIsLimitedByHeight() {
        let layout = StereoLayout.compute(container: screen, contentAspect: 0.5, settings: .default)
        #expect(layout.leftScreen.height <= screen.height * 0.9 + 0.001)
        #expect(abs(layout.leftScreen.width / layout.leftScreen.height - 0.5) < 0.001)
    }

    @Test func videoContentRectRemovesLetterbox() {
        let element = CGRect(x: 0, y: 100, width: 400, height: 400)
        let content = VideoGeometry.contentRect(element: element, videoSize: CGSize(width: 1920, height: 1080))
        #expect(content.width == 400)
        #expect(abs(content.height - 225) < 0.001)
        #expect(abs(content.midY - element.midY) < 0.001)
    }
}

// MARK: - Kalibrierung und Ausschnitt

@MainActor
struct CalibrationTests {
    private func makeDefaults() -> UserDefaults {
        let name = "DemonicVRTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func persistsAndReloads() {
        let defaults = makeDefaults()
        let store = CalibrationStore(defaults: defaults, key: "k")
        store.update {
            $0.screenScale = 0.7
            $0.horizontalSpacing = -0.1
            $0.verticalOffset = 0.25
            $0.cropEnabled = true
            $0.crop = NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6)
        }
        let reloaded = CalibrationStore(defaults: defaults, key: "k")
        #expect(reloaded.settings == store.settings)
        #expect(reloaded.settings.screenScale == 0.7)
        #expect(reloaded.settings.crop.width == 0.5)
    }

    @Test func resetRestoresDefaults() {
        let defaults = makeDefaults()
        let store = CalibrationStore(defaults: defaults, key: "k")
        store.update { $0.screenScale = 0.5 }
        store.reset()
        #expect(store.settings == .default)
        #expect(CalibrationStore(defaults: defaults, key: "k").settings == .default)
    }

    @Test func clampsOutOfRangeValues() {
        let defaults = makeDefaults()
        let store = CalibrationStore(defaults: defaults, key: "k")
        store.update {
            $0.screenScale = 5
            $0.horizontalSpacing = -3
            $0.crop = NormalizedRect(x: 0.95, y: -1, width: 0.5, height: 0)
        }
        #expect(store.settings.screenScale == CalibrationSettings.screenScaleRange.upperBound)
        #expect(store.settings.horizontalSpacing == CalibrationSettings.horizontalSpacingRange.lowerBound)
        #expect(store.settings.crop.x + store.settings.crop.width <= 1.0001)
        #expect(store.settings.crop.y == 0)
        #expect(store.settings.crop.height == NormalizedRect.minimumSize)
    }

    @Test func cropProducesExpectedPixelRect() throws {
        let rect = NormalizedRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25).pixelRect(width: 960, height: 540)
        #expect(rect == CGRect(x: 240, y: 270, width: 480, height: 135))

        let image = try #require(ReferenceScene.render(frame: 0))
        var settings = CalibrationSettings.default
        settings.cropEnabled = true
        settings.crop = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let cropped = FrameCropper.crop(image, settings: settings)
        #expect(cropped.width == image.width / 2)
        #expect(cropped.height == image.height / 2)

        settings.cropEnabled = false
        #expect(FrameCropper.crop(image, settings: settings) === image)
    }
}

// MARK: - Frame-Analyse, Referenzszene, Freigabe

@MainActor
struct FrameAnalysisTests {
    private func solidImage(gray: CGFloat, width: Int = 64, height: Int = 36) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test func detectsBlackAndRepeatedFrames() throws {
        let black = try #require(FrameFingerprint(image: solidImage(gray: 0)))
        let gray = try #require(FrameFingerprint(image: solidImage(gray: 0.5)))
        let gray2 = try #require(FrameFingerprint(image: solidImage(gray: 0.5)))
        #expect(black.isNearlyBlack)
        #expect(!gray.isNearlyBlack)
        #expect(!gray2.isNewFrame(comparedTo: gray))
        #expect(gray.isNewFrame(comparedTo: black))
        #expect(gray.isNewFrame(comparedTo: nil))
    }

    @Test func referenceSceneAnimatesAndHasExpectedSize() throws {
        let a = try #require(ReferenceScene.render(frame: 10))
        let b = try #require(ReferenceScene.render(frame: 11))
        #expect(a.width == Int(ReferenceScene.frameSize.width))
        #expect(a.height == Int(ReferenceScene.frameSize.height))
        let fa = try #require(FrameFingerprint(image: a))
        let fb = try #require(FrameFingerprint(image: b))
        #expect(fb.isNewFrame(comparedTo: fa))
        #expect(!fa.isNearlyBlack)
    }

    @Test func statisticsSeparateDeliveredAndNewFrames() {
        var stats = FrameStatistics(startedAt: 0)
        for i in 1...20 {
            stats.recordFrame(at: Double(i) * 0.1, duration: 0.01, isNew: i % 2 == 0, isBlack: false)
        }
        stats.recordError(at: 2.05, duration: 0.02)
        #expect(stats.delivered == 20)
        #expect(stats.newFrames == 10)
        #expect(stats.repeatedFrames == 10)
        #expect(stats.errors == 1)
        #expect(abs(stats.deliveredFPS(at: 2) - 10) < 0.001)
        #expect(abs(stats.newFPS(at: 2) - 5) < 0.001)
        #expect(stats.maxDuration == 0.02)
    }

    @Test func gateRequiresContinuousNewFrames() {
        var good = FrameStatistics(startedAt: 0)
        for i in 1...90 { good.recordFrame(at: Double(i) / 30, duration: 0.01, isNew: true, isBlack: false) }
        #expect(CardboardGate.health(good, at: 3.0) == .ok)

        // Eingefroren: danach nur noch wiederholte Frames.
        var frozen = good
        for i in 91...150 { frozen.recordFrame(at: Double(i) / 30, duration: 0.01, isNew: false, isBlack: false) }
        if case .stalled = CardboardGate.health(frozen, at: 5.0) {} else { Issue.record("Einfrieren nicht erkannt") }

        var black = FrameStatistics(startedAt: 0)
        for i in 1...90 { black.recordFrame(at: Double(i) / 30, duration: 0.01, isNew: i == 1, isBlack: true) }
        #expect(CardboardGate.health(black, at: 3.0) == .black)

        #expect(CardboardGate.health(FrameStatistics(startedAt: 0), at: 0.5) == .warmingUp)
        #expect(CardboardGate.health(FrameStatistics(), at: 10) == .noFrames)
    }

    @Test func sourcePolicy() {
        #expect(SourcePolicy.evaluate(.reference, acknowledged: false) == .allowed)
        #expect(SourcePolicy.evaluate(.youtubeSite, acknowledged: false) == .needsAcknowledgement)
        #expect(SourcePolicy.evaluate(.youtubeSite, acknowledged: true) == .allowed)
        if case .notPermitted = SourcePolicy.evaluate(.youtubeEmbed, acknowledged: true) {} else {
            Issue.record("IFrame-Player darf nicht verdeckt werden")
        }
        #expect(!SourcePolicy.canEnterCardboard(kind: .youtubeSite, acknowledged: true, health: .black))
        #expect(SourcePolicy.canEnterCardboard(kind: .youtubeSite, acknowledged: true, health: .ok))
        #expect(!SourcePolicy.canEnterCardboard(kind: .youtubeSite, acknowledged: false, health: .ok))
    }
}

// MARK: - Google OAuth (ohne Netzwerk)

@MainActor
struct GoogleOAuthTests {
    @Test func redirectSchemeIsReversedClientID() throws {
        let config = try #require(GoogleOAuthConfig(clientID: "1234567890-abcdefg.apps.googleusercontent.com"))
        #expect(config.redirectScheme == "com.googleusercontent.apps.1234567890-abcdefg")
        #expect(config.redirectURI == "com.googleusercontent.apps.1234567890-abcdefg:/oauth2redirect")
        #expect(GoogleOAuthConfig(clientID: "YOUR_CLIENT_ID.apps.googleusercontent.com") == nil)
    }

    @Test func pkceChallengeMatchesRFC7636Example() {
        // Beispiel aus RFC 7636, Anhang B.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(PKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(PKCE.makeVerifier().count >= 43)
    }
}

// MARK: - Bewegung und Spiegel-Modus

@MainActor
struct MirrorAndMotionTests {
    @Test func blackOrRareChangesAreNotMotion() {
        // Wie auf dem Gerät gemessen: fast nur schwarze, wiederholte Frames.
        var black = FrameStatistics(startedAt: 0)
        for i in 1...171 {
            black.recordFrame(at: Double(i) / 30, duration: 0.002, isNew: i <= 4, isBlack: i > 27)
        }
        #expect(!black.detectedMotion)

        var moving = FrameStatistics(startedAt: 0)
        for i in 1...60 { moving.recordFrame(at: Double(i) / 30, duration: 0.002, isNew: true, isBlack: false) }
        #expect(moving.detectedMotion)
    }

    @Test func mirrorSourceRectUsesVideoAndCrop() {
        let page = CGSize(width: 402, height: 700)
        let video = CGRect(x: 0, y: 48, width: 402, height: 226)
        #expect(MirrorCinemaContainer.sourceRect(video: video, page: page, crop: .full) == video)
        let half = MirrorCinemaContainer.sourceRect(video: video, page: page,
                                                    crop: NormalizedRect(x: 0.5, y: 0, width: 0.5, height: 1))
        #expect(half == CGRect(x: 201, y: 48, width: 201, height: 226))
        #expect(MirrorCinemaContainer.sourceRect(video: nil, page: page, crop: .full) == CGRect(origin: .zero, size: page))
    }

    @Test func mirrorNeedsPlayingYouTubeVideo() {
        let player = PlayerController(startURL: nil)
        #expect(!player.mirrorReadiness(acknowledged: true).ready)
    }
}

// MARK: - Spiegel-Modus: Begrenzung pro Augenhälfte (Regression)

@MainActor
struct MirrorClippingRegressionTests {
    nonisolated private static func settings(scale: Double, spacing: Double, vertical: Double = 0,
                                 crop: NormalizedRect? = nil) -> CalibrationSettings {
        var s = CalibrationSettings.default
        s.screenScale = scale
        s.horizontalSpacing = spacing
        s.verticalOffset = vertical
        if let crop {
            s.cropEnabled = true
            s.crop = crop
        }
        return s
    }

    /// Erlaubte Werte einschließlich der Grenzen.
    nonisolated static let cases: [CalibrationSettings] = [
        settings(scale: 0.9, spacing: -0.25),                 // Beispiel aus dem Review
        settings(scale: 0.9, spacing: 0.25),
        settings(scale: 1.0, spacing: -0.25),
        settings(scale: 1.0, spacing: 0.25),
        settings(scale: 1.0, spacing: 0),
        settings(scale: 0.4, spacing: -0.25, vertical: -0.5),
        settings(scale: 0.4, spacing: 0.25, vertical: 0.5),
        settings(scale: 1.0, spacing: -0.25, vertical: 0.5),
        settings(scale: 0.9, spacing: -0.25, crop: NormalizedRect(x: 0.6, y: 0.1, width: 0.4, height: 0.9)),
        settings(scale: 1.0, spacing: 0.25, crop: NormalizedRect(x: 0, y: 0, width: 0.1, height: 1)),
    ]

    private struct Measured {
        var layout: StereoLayout
        var left: CGRect    // Instanz 0 (echte Ebene) im Container
        var right: CGRect   // Instanz 1 (replizierte Kopie) im Container
        var screenOfSource: CGRect
        var clips: Bool
        var instances: Int
    }

    private func measure(container size: CGSize, page: CGSize, settings: CalibrationSettings) -> Measured {
        let view = MirrorCinemaContainer(frame: CGRect(origin: .zero, size: size))
        view.settings = settings
        view.videoRect = nil
        view.applyLayout(pageSize: page)

        let replicator = view.layer as! CAReplicatorLayer
        let shift = CATransform3DGetAffineTransform(replicator.instanceTransform)
        let left = view.eyeClipView.frame
        let right = left.applying(shift)

        let source = MirrorCinemaContainer.sourceRect(video: nil, page: page, crop: settings.effectiveCrop)
        let layout = StereoLayout.compute(container: size,
                                          contentAspect: source.width / source.height,
                                          settings: settings)
        let mapped = view.stageView.convert(source, to: view)
        return Measured(layout: layout, left: left, right: right, screenOfSource: mapped,
                        clips: view.eyeClipView.clipsToBounds, instances: replicator.instanceCount)
    }

    private func inside(_ inner: CGRect, _ outer: CGRect, tolerance: CGFloat = 0.01) -> Bool {
        inner.minX >= outer.minX - tolerance && inner.maxX <= outer.maxX + tolerance &&
            inner.minY >= outer.minY - tolerance && inner.maxY <= outer.maxY + tolerance
    }

    private func close(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 0.01) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance &&
            abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    @Test func reviewExampleNoLongerOverlaps() {
        let m = measure(container: CGSize(width: 800, height: 400),
                        page: CGSize(width: 1600, height: 900),
                        settings: MirrorClippingRegressionTests.cases[0])
        // StereoLayout selbst: links 70–430, rechts 370–730 (60 pt Überlappung).
        #expect(abs(m.layout.leftScreen.minX - 70) < 0.01 && abs(m.layout.leftScreen.maxX - 430) < 0.01)
        #expect(abs(m.layout.rightScreen.minX - 370) < 0.01 && abs(m.layout.rightScreen.maxX - 730) < 0.01)
        // Tatsächlich sichtbar: links 100–400, Kopie rechts 400–700.
        #expect(abs(m.left.minX - 100) < 0.01 && abs(m.left.maxX - 400) < 0.01)
        #expect(abs(m.right.minX - 400) < 0.01 && abs(m.right.maxX - 700) < 0.01)
        #expect(!m.left.intersects(m.right))
    }

    @Test(arguments: MirrorClippingRegressionTests.cases)
    func bothInstancesStayInTheirEyeHalf(_ settings: CalibrationSettings) {
        for size in [CGSize(width: 800, height: 400), CGSize(width: 874, height: 402)] {
            let m = measure(container: size, page: CGSize(width: 402, height: 226), settings: settings)
            #expect(m.instances == 2)
            #expect(m.clips)
            #expect(!m.left.isEmpty)
            // Echte Ebene in der linken, replizierte Kopie in der rechten Augenhälfte.
            #expect(inside(m.left, m.layout.leftEye), "links \(m.left) außerhalb \(m.layout.leftEye)")
            #expect(inside(m.right, m.layout.rightEye), "rechts \(m.right) außerhalb \(m.layout.rightEye)")
            #expect(!m.left.intersects(m.right))
            // Sichtbar ist nur Leinwand, und die Kopie liegt auf der rechten Leinwand.
            #expect(inside(m.left, m.layout.leftScreen))
            #expect(inside(m.right, m.layout.rightScreen))
            // Größe, Abstand, vertikale Position und Ausschnitt bleiben wirksam:
            // Der Quellbereich füllt genau die berechnete linke Leinwand.
            #expect(close(m.screenOfSource, m.layout.leftScreen), "\(m.screenOfSource) ≠ \(m.layout.leftScreen)")
        }
    }

    @Test func withoutOverlapTheWholeScreenIsVisible() {
        let s = Self.settings(scale: 0.9, spacing: 0.1)
        let m = measure(container: CGSize(width: 874, height: 402), page: CGSize(width: 402, height: 226), settings: s)
        #expect(close(m.left, m.layout.leftScreen))
        #expect(close(m.right, m.layout.rightScreen))
    }
}

// MARK: - Spiegel-Vergleichstest

@MainActor
struct MirrorComparisonTests {
    private func makeContainer(_ mode: MirrorDisplayMode, spacing: Double = -0.25, scale: Double = 0.9)
        -> (MirrorCinemaContainer, MirrorGeometry, StereoLayout) {
        var settings = CalibrationSettings.default
        settings.screenScale = scale
        settings.horizontalSpacing = spacing
        let view = MirrorCinemaContainer(frame: CGRect(x: 0, y: 0, width: 800, height: 400))
        view.settings = settings
        view.mode = mode
        let geometry = view.applyLayout(pageSize: CGSize(width: 1600, height: 900))!
        let layout = StereoLayout.compute(container: CGSize(width: 800, height: 400),
                                          contentAspect: 16.0 / 9.0, settings: settings)
        return (view, geometry, layout)
    }

    private func inside(_ inner: CGRect, _ outer: CGRect) -> Bool {
        inner.minX >= outer.minX - 0.01 && inner.maxX <= outer.maxX + 0.01 &&
            inner.minY >= outer.minY - 0.01 && inner.maxY <= outer.maxY + 0.01
    }

    @Test func standardModePutsOriginalLeftAndReplicaRight() {
        let (view, g, layout) = makeContainer(.originalLeft)
        let replicator = view.layer as! CAReplicatorLayer
        let replica = view.eyeClipView.frame.applying(CATransform3DGetAffineTransform(replicator.instanceTransform))
        #expect(replicator.instanceCount == 2)
        #expect(inside(view.eyeClipView.frame, layout.leftEye))   // Instanz 0 = Original = links
        #expect(inside(replica, layout.rightEye))                 // Instanz 1 = Replikat = rechts
        #expect(g.originalRect == view.eyeClipView.frame)
        #expect(g.replicaRect == replica)
        #expect(MirrorDisplayMode.originalLeft.role(leftHalf: true) == "Original-WebView")
        #expect(MirrorDisplayMode.originalLeft.role(leftHalf: false) == "Replikat (CAReplicatorLayer)")
    }

    @Test(arguments: [-0.25, 0.0, 0.25])
    func swappedModePutsOriginalRightAndReplicaLeft(_ spacing: Double) {
        let (view, g, layout) = makeContainer(.originalRight, spacing: spacing)
        let replicator = view.layer as! CAReplicatorLayer
        let replica = view.eyeClipView.frame.applying(CATransform3DGetAffineTransform(replicator.instanceTransform))
        #expect(replicator.instanceCount == 2)
        #expect(inside(view.eyeClipView.frame, layout.rightEye))
        #expect(inside(replica, layout.leftEye))
        #expect(!view.eyeClipView.frame.intersects(replica))
        // Quelle füllt die rechte Leinwand.
        let mapped = view.stageView.convert(g.sourceRect, to: view)
        #expect(abs(mapped.minX - layout.rightScreen.minX) < 0.01)
        #expect(abs(mapped.width - layout.rightScreen.width) < 0.01)
        #expect(MirrorDisplayMode.originalRight.role(leftHalf: true) == "Replikat (CAReplicatorLayer)")
    }

    @Test func originalOnlyModeHasNoReplica() {
        let (view, g, layout) = makeContainer(.originalOnly)
        let replicator = view.layer as! CAReplicatorLayer
        #expect(replicator.instanceCount == 1)
        #expect(g.instanceCount == 1)
        #expect(inside(view.eyeClipView.frame, layout.leftEye))
        // Ohne Replikat wird nur an der eigenen Augenhälfte beschnitten.
        #expect(abs(view.eyeClipView.frame.minX - layout.leftScreen.minX) < 0.01)
    }

    @Test func localTestPageIsClassifiedAndAllowed() {
        let page = URL(fileURLWithPath: "/var/containers/Bundle/Application/X/Demonic VR.app/MirrorTestPage.html")
        #expect(PlayerController.classify(page, embedVideoID: nil) == .localVideoTest)
        #expect(PlayerController.classify(URL(fileURLWithPath: "/tmp/other.html"), embedVideoID: nil) == .other)
        #expect(SourcePolicy.evaluate(.localVideoTest, acknowledged: false) == .allowed)
        let root = URL(fileURLWithPath: "/app/Demonic VR.app")
        #expect(PlayerController.isBundleFile(URL(fileURLWithPath: "/app/Demonic VR.app/MirrorTestPage.html"), bundleRoot: root))
        #expect(!PlayerController.isBundleFile(URL(fileURLWithPath: "/app/Demonic VR.app2/x.html"), bundleRoot: root))
        #expect(!PlayerController.isBundleFile(URL(fileURLWithPath: "/etc/passwd"), bundleRoot: root))
    }

    @Test func testPageAndVideoAreBundled() throws {
        let page = try #require(PlayerController.localMirrorTestPage)
        let html = try String(contentsOf: page, encoding: .utf8)
        #expect(html.contains("<video"))
        #expect(html.contains("playsinline"))
        #expect(html.contains("MirrorTestVideo.mp4"))
        let video = page.deletingLastPathComponent().appendingPathComponent("MirrorTestVideo.mp4")
        #expect(FileManager.default.fileExists(atPath: video.path))
    }

    @Test func reportContainsRequiredFieldsAndNoSecrets() {
        let session = MirrorTestSession()
        var status = PlaybackStatus()
        status.hasVideo = true
        status.currentTime = 3
        status.videoSize = CGSize(width: 1280, height: 720)
        session.mode = .originalLeft
        session.begin(source: .localVideoTest, calibration: .default, status: status,
                      webViewSize: CGSize(width: 402, height: 640))
        session.updateGeometry(MirrorGeometry(containerSize: CGSize(width: 874, height: 402),
                                              pageSize: CGSize(width: 402, height: 640),
                                              videoRect: CGRect(x: 0, y: 48, width: 402, height: 226),
                                              sourceRect: CGRect(x: 0, y: 48, width: 402, height: 226),
                                              originalRect: CGRect(x: 21, y: 78, width: 393, height: 221),
                                              replicaRect: CGRect(x: 458, y: 78, width: 393, height: 221),
                                              instanceCount: 2))
        let run = session.currentRun!
        session.setObservation(runID: run.id, leftHalf: true, video: .black, overlay: .visible)
        session.setObservation(runID: run.id, leftHalf: false, video: .visibleMoving, overlay: .visible)
        status.currentTime = 9
        session.finish(status: status)

        let env = ReportEnvironment(appVersion: "1.0", build: "1", systemName: "iOS",
                                    systemVersion: "26.2", deviceModel: "iPhone18,1")
        let report = session.report(environment: env)
        for expected in ["Demonic VR 1.0 (Build 1)", "iOS 26.2", "Lokales Testvideo", "Original links · Replikat rechts",
                         "Kalibrierung: Größe 90 %", "WebView-Größe: 402×640 pt", "Erkanntes Videorechteck",
                         "MANUELL LINKS:  Video: Videobild schwarz", "MANUELL RECHTS: Video: Videobild sichtbar und bewegt",
                         "replizierte Instanz", "bestätigt keine sichtbare Videowiedergabe"] {
            #expect(report.contains(expected), "fehlt: \(expected)")
        }
        for forbidden in ["http", "cookie", "Cookie", "token", "Token", "file://"] {
            #expect(!report.contains(forbidden), "darf nicht enthalten: \(forbidden)")
        }
    }

    @Test func assessmentNeverClaimsDRM() {
        var run = MirrorTestRun(startedAt: Date(), source: .youtubeSite, mode: .originalLeft,
                                calibration: .default, videoNaturalSize: .zero)
        run.left.video = .black
        run.right.video = .visibleMoving
        let text = MirrorDiagnosticReport.assessment(run)
        #expect(text.contains("replizierte Instanz"))
        #expect(text.contains("keinen Inhaltsschutz"))
        run.mode = .originalRight
        #expect(MirrorDiagnosticReport.assessment(run).contains("Original-Instanz"))
    }
}

// MARK: - Auswertung des Geräteberichts (zwei Replikate, Seitengröße, Einordnung)

@MainActor
struct MirrorDeviceFindingsTests {
    @Test(arguments: [-0.25, 0.0, 0.25])
    func twoReplicasHideOriginalAndFillBothHalves(_ spacing: Double) throws {
        var settings = CalibrationSettings.default
        settings.horizontalSpacing = spacing
        let view = MirrorCinemaContainer(frame: CGRect(x: 0, y: 0, width: 874, height: 402))
        view.settings = settings
        view.mode = .twoReplicas
        let g = try #require(view.applyLayout(pageSize: CGSize(width: 402, height: 523)))
        let layout = StereoLayout.compute(container: CGSize(width: 874, height: 402),
                                          contentAspect: 402.0 / 523.0, settings: settings)
        let replicator = view.layer as! CAReplicatorLayer
        let step = CATransform3DGetAffineTransform(replicator.instanceTransform)
        let original = view.eyeClipView.frame
        let first = original.applying(step)
        let second = first.applying(step)
        #expect(replicator.instanceCount == 3)
        #expect(first == g.replicaRect)
        #expect(second == g.secondReplicaRect)
        // Replikat 1 links, Replikat 2 rechts, je in ihrer Augenhälfte.
        #expect(first.minX >= layout.leftEye.minX - 0.01 && first.maxX <= layout.leftEye.maxX + 0.01)
        #expect(second.minX >= layout.rightEye.minX - 0.01 && second.maxX <= layout.rightEye.maxX + 0.01)
        // Das Original wird von der Maske nicht durchgelassen, die Replikate schon.
        let mask = try #require(view.layer.mask as? CAShapeLayer)
        let path = try #require(mask.path)
        #expect(path.contains(CGPoint(x: first.midX, y: first.midY)))
        #expect(path.contains(CGPoint(x: second.midX, y: second.midY)))
        #expect(!path.contains(CGPoint(x: original.midX, y: original.midY)))
        #expect(!original.intersects(first))
        // Andere Anordnungen haben keine Maske.
        view.mode = .originalLeft
        view.applyLayout(pageSize: CGSize(width: 402, height: 523))
        #expect(view.layer.mask == nil)
        #expect(replicator.instanceCount == 2)
    }

    @Test func mirrorPageSizeRejectsLandscapeStrip() {
        // Gerätebericht Durchlauf 4: 750×127 pt nach Querformat-Umbruch.
        let fixed = MirrorCinemaContainer.mirrorPageSize(for: CGSize(width: 750, height: 127))
        #expect(fixed.width == 430)
        #expect(fixed.height >= fixed.width * 1.3)
        // Normale Hochformat-Größen bleiben unverändert.
        #expect(MirrorCinemaContainer.mirrorPageSize(for: CGSize(width: 402, height: 523)) == CGSize(width: 402, height: 523))
    }

    @Test func assessmentForOriginalOnlyAndTwoReplicas() {
        var run = MirrorTestRun(startedAt: Date(), source: .localVideoTest, mode: .originalOnly,
                                calibration: .default, videoNaturalSize: .zero)
        run.left.video = .visibleMoving
        #expect(MirrorDiagnosticReport.assessment(run) == "Original allein zeigt bewegtes Video.")
        run.mode = .twoReplicas
        run.right.video = .black
        #expect(MirrorDiagnosticReport.assessment(run).contains("nur in Replikat 1"))
        run.left.video = .black
        run.right.video = .visibleMoving
        #expect(MirrorDiagnosticReport.assessment(run).contains("zuletzt gezeichnete Instanz"))
        run.left.video = .visibleMoving
        #expect(MirrorDiagnosticReport.assessment(run).contains("beiden Replikaten"))
    }
}

// MARK: - Brillentaste und Wiedergabesteuerung

@MainActor
struct HeadsetButtonTests {
    @Test func zoneSitsOnTheCenterLineOverFullHeight() {
        let size = CGSize(width: 874, height: 402)
        let zone = HeadsetButtonZone.zone(in: size)
        #expect(zone.width == 72)
        #expect(zone.height == size.height)
        #expect(abs(zone.midX - size.width / 2) < 0.001)
    }

    @Test func zoneDoesNotCoverMirroredScreensBeyondItsStrip() {
        // Standard-Kalibrierung: Die Leinwände enden vor dem Streifen bzw. nur knapp darin.
        let size = CGSize(width: 874, height: 402)
        let layout = StereoLayout.compute(container: size, contentAspect: 16.0 / 9.0, settings: .default)
        let zone = HeadsetButtonZone.zone(in: size)
        #expect(layout.leftScreen.maxX - zone.minX < 36)
        #expect(zone.maxX - layout.rightScreen.minX < 36)
    }

    @Test func playbackScriptUsesOnlyDocumentedControls() {
        let toggle = PlayerController.playbackScript(.toggle)
        #expect(toggle.contains("('toggle')"))
        #expect(toggle.contains("pauseVideo"))      // IFrame Player API
        #expect(toggle.contains("best.pause()"))    // HTMLMediaElement
        let seek = PlayerController.playbackScript(.seek(seconds: -10))
        #expect(seek.contains("('seek:-10.0')"))
        #expect(!seek.contains(".src"))
        #expect(!seek.contains("currentSrc"))
    }
}

// MARK: - Oberfläche: In VR ansehen, Einstellungen

@MainActor
struct VRStartAndSettingsTests {
    @Test func vrUsesTheTestedTwoReplicaConfiguration() {
        #expect(AppModel.vrMirrorMode == .twoReplicas)
        #expect(AppModel.vrMirrorMode.instanceCount == 3)
    }

    @Test func vrWithoutVideoExplainsInsteadOfStarting() {
        let model = AppModel(environment: AppEnvironment(isUITest: true))
        let result = model.startVR()
        if case .unavailable(let message) = result {
            #expect(message.contains("Video"))
        } else {
            Issue.record("VR darf ohne Video nicht starten: \(result)")
        }
        #expect(model.screen == .player)
        #expect(model.player.webView == nil) // nichts wurde erzeugt oder geladen
    }

    @Test func developerOptionsDefaultOffAndPersist() {
        let model = AppModel(environment: AppEnvironment(isUITest: true))
        #expect(model.showDeveloperOptions == false)
        model.setShowDeveloperOptions(true)
        #expect(model.showDeveloperOptions)
        #expect(UserDefaults(suiteName: "DemonicVR.UITests")?.bool(forKey: AppModel.developerOptionsKey) == true)
        let forced = AppModel(environment: AppEnvironment(isUITest: true, forceDeveloperOptions: true))
        #expect(forced.showDeveloperOptions)
    }

    @Test func togglingSettingsKeepsTheSameWebView() {
        let model = AppModel(environment: AppEnvironment(isUITest: true))
        let webView = model.player.hostedWebView()
        model.sheet = .settings
        model.setShowDeveloperOptions(true)
        model.setShowDeveloperOptions(false)
        model.sheet = nil
        #expect(model.player.hostedWebView() === webView)
    }

    @Test func stopCommandPausesAndRewinds() {
        let script = PlayerController.playbackScript(.stop)
        #expect(script.contains("('stop')"))
        #expect(script.contains("best.pause(); best.currentTime = 0"))
        #expect(script.contains("p.pauseVideo(); p.seekTo(0, true)"))
    }
}
