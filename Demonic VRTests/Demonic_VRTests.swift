//
//  Demonic_VRTests.swift
//  Demonic VRTests
//
//  Created by David Martens on 22.11.26.
//

import CoreGraphics
import Foundation
import Testing
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
