//
//  PlayerController.swift
//  Demonic VR
//
//  Besitzt die einzige, persistente WKWebView der App. Sie wird einmal
//  erzeugt, nie neu angelegt und nie aus der View-Hierarchie entfernt.
//  Damit bleiben Sitzung, Wiedergabe, Position und Audio bei jedem
//  Ansichtswechsel erhalten.
//

import Foundation
import Observation
import UIKit
import WebKit

nonisolated enum PlayerPageKind: Equatable, Sendable {
    case blank
    case youtubeSite
    case embed(videoID: String)
    /// Mitgelieferte Spiegeltest-Seite mit lokalem HTML-<video> (MirrorTestPage.html).
    case localVideoTest
    case other
}

nonisolated struct PlaybackStatus: Equatable, Sendable {
    var hasVideo = false
    var currentTime: Double = 0
    var duration: Double = 0
    var isPaused = true
    var readyState = 0
    var elementRect: CGRect = .zero
    var videoSize: CGSize = .zero
    var updatedAt: Date = .distantPast

    var contentRect: CGRect {
        VideoGeometry.contentRect(element: elementRect, videoSize: videoSize)
    }
}

nonisolated struct CaptureRegion: Equatable, Sendable {
    enum Source: String, Sendable {
        case videoElement = "Video-Element"
        case embedPlayer = "IFrame-Player"
        case wholeView = "Gesamte WebView"
    }
    var rect: CGRect
    var source: Source
}

nonisolated struct PlayerIssue: Identifiable, Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case openOnYouTube(URL)
        case goHome
        case retry
        case dismiss

        var title: String {
            switch self {
            case .openOnYouTube: return "In YouTube-Ansicht öffnen"
            case .goHome: return "Zur YouTube-Startseite"
            case .retry: return "Erneut versuchen"
            case .dismiss: return "Schließen"
            }
        }

        var identifier: String {
            switch self {
            case .openOnYouTube: return "issue.openOnYouTube"
            case .goHome: return "issue.home"
            case .retry: return "issue.retry"
            case .dismiss: return "issue.dismiss"
            }
        }
    }

    let id = UUID()
    var title: String
    var message: String
    var actions: [Action]
}

/// Momentaufnahme für die Prüfung „gleiche Sitzung nach Ansichtswechsel“.
nonisolated struct ContinuityMark: Equatable, Sendable {
    var webViewID: ObjectIdentifier?
    var url: URL?
    var currentTime: Double
    var isPaused: Bool
    var hasVideo: Bool
    var date: Date
}

nonisolated struct ContinuityReport: Equatable, Sendable {
    var before: ContinuityMark
    var after: ContinuityMark

    var sameWebView: Bool { before.webViewID != nil && before.webViewID == after.webViewID }
    var sameURL: Bool { Self.normalized(before.url) == Self.normalized(after.url) }

    /// Wiedergabe wurde nicht auf 0 zurückgesetzt und ist (falls sie lief) weitergelaufen.
    var positionPreserved: Bool {
        guard before.hasVideo else { return true }
        guard after.hasVideo else { return false }
        if before.currentTime < 1 { return true }
        return after.currentTime >= before.currentTime - 1.0
    }

    var isContinuous: Bool { sameWebView && sameURL && positionPreserved }

    var summary: String {
        let position = before.hasVideo
            ? "\(TimeFormatter.clock(before.currentTime)) → \(TimeFormatter.clock(after.currentTime))"
            : "kein Video"
        return "WebView \(sameWebView ? "gleich" : "NEU") · Seite \(sameURL ? "gleich" : "geändert") · Position \(position)"
    }

    private static func normalized(_ url: URL?) -> String {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "" }
        components.queryItems = components.queryItems?.filter { $0.name != "t" }
        components.fragment = nil
        return components.string ?? url.absoluteString
    }
}

nonisolated enum TimeFormatter {
    static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

@Observable
final class PlayerController: NSObject {
    static let homeURL = URL(string: "https://m.youtube.com/")!
    /// Herkunft der lokalen IFrame-Seite: https://<Bundle-ID>, wie von YouTube für App-WebViews empfohlen.
    static let embedOrigin = URL(string: "https://me.thedemonlord333.demonic-vr/")!
    nonisolated static let messageHandlerName = "demonic"
    private static let preferEmbedKey = "demonicvr.preferEmbedPlayer"

    /// Die eine WebView. Sie wird erst erzeugt, wenn sie zum ersten Mal angezeigt wird
    /// (siehe `hostedWebView()`): Eine vor dem App-Fenster erzeugte WKWebView lässt
    /// iOS 26 beim ersten Tipp in `-[UIGestureRecognizer _delayTouchesForEvent:inPhase:]` abstürzen.
    @ObservationIgnored private(set) var webView: WKWebView?
    @ObservationIgnored private var pendingLoad: PendingLoad?
    /// Normaler Platz der WebView in der Startansicht.
    @ObservationIgnored weak var homeContainer: WebViewContainer?
    /// `true`, solange der Spiegel-Modus die WebView anzeigt.
    @ObservationIgnored private(set) var isWebViewLent = false
    /// Nur während einer Spiegel-Sitzung darf MirrorCinemaView die WebView übernehmen.
    @ObservationIgnored var mirrorSessionActive = false
    @ObservationIgnored private let startURL: URL?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var embedVideoID: String?
    @ObservationIgnored private var lastRequestedURL: URL?

    private enum PendingLoad {
        case url(URL)
        case embed(videoID: String, start: Int)
        case localFile(URL)
    }

    /// Lokale Spiegeltest-Seite im App-Bundle (lädt MirrorTestVideo.mp4).
    static var localMirrorTestPage: URL? {
        Bundle.main.url(forResource: "MirrorTestPage", withExtension: "html")
    }

    /// Kennung der WebView, sobald sie existiert (beobachtbar für die Anzeige).
    private(set) var webViewID: ObjectIdentifier?
    private(set) var pageKind: PlayerPageKind = .blank
    private(set) var currentURL: URL?
    private(set) var title = ""
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var status = PlaybackStatus()
    var issue: PlayerIssue?
    /// Eingefügte Video-Links im offiziellen IFrame-Player statt in der YouTube-Ansicht öffnen.
    private(set) var preferEmbedPlayer: Bool

    func setPreferEmbedPlayer(_ value: Bool) {
        preferEmbedPlayer = value
        UserDefaults.standard.set(value, forKey: Self.preferEmbedKey)
    }

    var webViewShortID: String {
        guard let webViewID else { return "–" }
        return String(UInt(bitPattern: webViewID.hashValue) & 0xFFFFFF, radix: 16, uppercase: true)
    }

    var sourceKind: FrameSourceKind {
        switch pageKind {
        case .youtubeSite: return .youtubeSite
        case .embed: return .youtubeEmbed
        case .localVideoTest: return .localVideoTest
        case .other: return .otherWeb
        case .blank: return .none
        }
    }

    /// - Parameter startURL: Erste Seite. `nil` lädt nichts (UI-Tests ohne Netzwerk).
    init(startURL: URL? = PlayerController.homeURL) {
        self.startURL = startURL
        self.preferEmbedPlayer = UserDefaults.standard.bool(forKey: Self.preferEmbedKey)
        super.init()
        if let startURL {
            pendingLoad = .url(startURL)
            lastRequestedURL = startURL
        }
    }

    /// Liefert die eine WebView und erzeugt sie beim ersten Aufruf. Wird von `WebViewHost`
    /// aufgerufen, wenn das App-Fenster bereits existiert.
    func hostedWebView() -> WKWebView {
        if let webView { return webView }

        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        configuration.userContentController.add(ScriptMessageProxy(target: self), name: Self.messageHandlerName)
        configuration.userContentController.addUserScript(WKUserScript(source: Self.statusScript,
                                                                       injectionTime: .atDocumentEnd,
                                                                       forMainFrameOnly: true))

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = true
        webView.accessibilityIdentifier = "player.webview"
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView
        observeWebView(webView)

        // Beobachtbaren Zustand erst nach dem laufenden View-Update ändern.
        let identifier = ObjectIdentifier(webView)
        Task { @MainActor [weak self] in self?.webViewID = identifier }

        if let pending = pendingLoad {
            pendingLoad = nil
            switch pending {
            case .url(let url): webView.load(URLRequest(url: url))
            case .embed(let videoID, let start): loadEmbedPage(in: webView, videoID: videoID, start: start)
            case .localFile(let url): loadBundleFile(url, in: webView)
            }
        }
        return webView
    }

    // MARK: - Navigation

    func goHome() {
        issue = nil
        load(startURL ?? Self.homeURL)
    }

    func goBack() {
        if let webView, webView.canGoBack { webView.goBack() }
    }

    func reload() {
        issue = nil
        if let webView, webView.url != nil {
            webView.reload()
        } else if let lastRequestedURL {
            load(lastRequestedURL)
        }
    }

    /// Öffnet eingefügten Text als YouTube-Link. Gibt `false` zurück, wenn er nicht erkannt wurde.
    @discardableResult
    func open(input: String) -> Bool {
        guard let link = YouTubeLink.parse(input) else {
            issue = PlayerIssue(
                title: "Kein abspielbarer YouTube-Link",
                message: "„\(input.prefix(80))“ wurde nicht als YouTube-Video, Playlist oder YouTube-Seite erkannt. Unterstützt: youtube.com/watch?v=…, youtu.be/…, /shorts/…, /live/…, Playlists.",
                actions: [.dismiss, .goHome]
            )
            return false
        }
        open(link)
        return true
    }

    func open(_ link: YouTubeLink) {
        issue = nil
        if preferEmbedPlayer, let id = link.videoID {
            loadEmbed(videoID: id, start: link.startSeconds ?? 0)
        } else {
            load(link.siteURL)
        }
    }

    private func load(_ url: URL) {
        lastRequestedURL = url
        embedVideoID = nil
        if let webView {
            webView.load(URLRequest(url: url))
        } else {
            pendingLoad = .url(url)
        }
    }

    func loadEmbed(videoID: String, start: Int) {
        guard YouTubeLink.isValidVideoID(videoID) else { return }
        embedVideoID = videoID
        lastRequestedURL = YouTubeLink.video(id: videoID, start: start).siteURL
        if let webView {
            loadEmbedPage(in: webView, videoID: videoID, start: start)
        } else {
            pendingLoad = .embed(videoID: videoID, start: start)
        }
    }

    private func loadEmbedPage(in webView: WKWebView, videoID: String, start: Int) {
        webView.loadHTMLString(EmbedPlayerPage.html(videoID: videoID, start: start, origin: Self.embedOrigin),
                               baseURL: Self.embedOrigin)
    }

    func perform(_ action: PlayerIssue.Action) {
        switch action {
        case .openOnYouTube(let url):
            issue = nil
            load(url)
        case .goHome:
            goHome()
        case .retry:
            reload()
        case .dismiss:
            issue = nil
        }
    }

    // MARK: - Lokaler Spiegeltest

    /// Lädt die mitgelieferte Testseite mit lokalem, ungeschütztem HTML-<video> in dieselbe WebView.
    /// Die YouTube-Seite wird dabei verlassen (Cookies/Anmeldung bleiben im Datenspeicher erhalten);
    /// zurück geht es über „Zurück“ oder „YouTube“.
    @discardableResult
    func loadLocalMirrorTest() -> Bool {
        guard let url = Self.localMirrorTestPage else {
            issue = PlayerIssue(title: "Testseite fehlt",
                                message: "MirrorTestPage.html ist nicht im App-Bundle.",
                                actions: [.dismiss])
            return false
        }
        issue = nil
        embedVideoID = nil
        lastRequestedURL = url
        if let webView {
            loadBundleFile(url, in: webView)
        } else {
            pendingLoad = .localFile(url)
        }
        return true
    }

    private func loadBundleFile(_ url: URL, in webView: WKWebView) {
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    /// Nur Dateien aus dem App-Bundle dürfen als file:// geladen werden.
    nonisolated static func isBundleFile(_ url: URL, bundleRoot: URL?) -> Bool {
        guard url.isFileURL, let root = bundleRoot?.standardizedFileURL.path else { return false }
        let path = url.standardizedFileURL.path
        return path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    // MARK: - Spiegel-Modus

    /// Der Spiegel-Modus übernimmt dieselbe WebView-Instanz (kein Neuladen).
    func lendWebView() {
        isWebViewLent = true
    }

    /// Bringt die WebView zurück an ihren Platz in der Startansicht.
    func returnWebViewHome() {
        guard isWebViewLent else { return }
        isWebViewLent = false
        homeContainer?.attachIfPossible()
    }

    /// Voraussetzungen für den Spiegel-Modus: Quelle freigegeben und ein laufendes Video erkannt.
    func mirrorReadiness(acknowledged: Bool, now: Date = Date()) -> (ready: Bool, message: String) {
        switch SourcePolicy.evaluate(sourceKind, acknowledged: acknowledged) {
        case .notPermitted(let reason): return (false, reason)
        case .needsAcknowledgement: return (false, "Bitte die Hinweise bestätigen.")
        case .allowed: break
        }
        guard status.hasVideo, now.timeIntervalSince(status.updatedAt) < 3 else {
            return (false, sourceKind == .localVideoTest
                    ? "Testvideo noch nicht erkannt – kurz warten oder „Play“ auf der Testseite antippen."
                    : "Kein Video auf der Seite erkannt. Video in der YouTube-Ansicht öffnen.")
        }
        guard !status.isPaused else {
            return (false, "Video ist pausiert. Bitte starten, dann Cardboard öffnen.")
        }
        return (true, "Video läuft – Spiegel-Modus möglich.")
    }

    // MARK: - Snapshot-Bereich und Sitzung

    /// Bereich der WebView, der für Snapshots aufgenommen wird (in View-Koordinaten).
    func captureRegion(now: Date = Date()) -> CaptureRegion? {
        guard let webView, webView.window != nil else { return nil }
        let bounds = webView.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        if status.hasVideo, now.timeIntervalSince(status.updatedAt) < 3 {
            let rect = status.contentRect.intersection(bounds)
            if !rect.isNull, rect.width >= 16, rect.height >= 16 {
                let source: CaptureRegion.Source
                if case .embed = pageKind { source = .embedPlayer } else { source = .videoElement }
                return CaptureRegion(rect: rect.integral.intersection(bounds), source: source)
            }
        }
        return CaptureRegion(rect: bounds, source: .wholeView)
    }

    func continuityMark() -> ContinuityMark {
        ContinuityMark(webViewID: webView.map(ObjectIdentifier.init),
                       url: webView?.url,
                       currentTime: status.currentTime,
                       isPaused: status.isPaused,
                       hasVideo: status.hasVideo,
                       date: Date())
    }

    // MARK: - Interna

    private func observeWebView(_ webView: WKWebView) {
        observations = [
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.isLoading = webView.isLoading }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.title = webView.title ?? "" }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoBack = webView.canGoBack }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.urlDidChange(webView.url) }
            },
        ]
    }

    private func urlDidChange(_ url: URL?) {
        currentURL = url
        pageKind = Self.classify(url, embedVideoID: embedVideoID)
        status = PlaybackStatus()
    }

    static func classify(_ url: URL?, embedVideoID: String?) -> PlayerPageKind {
        guard let url, let scheme = url.scheme?.lowercased() else { return .blank }
        if scheme == "about" { return .blank }
        if url.isFileURL {
            return url.lastPathComponent == "MirrorTestPage.html" ? .localVideoTest : .other
        }
        let host = url.host?.lowercased() ?? ""
        if host == embedOrigin.host?.lowercased() {
            return embedVideoID.map { .embed(videoID: $0) } ?? .other
        }
        if host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be" {
            return .youtubeSite
        }
        return .other
    }

    fileprivate func handleScriptMessage(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }
        switch type {
        case "status":
            var next = PlaybackStatus()
            next.updatedAt = Date()
            if let rect = message["rect"] as? [Double], rect.count == 4 {
                next.hasVideo = rect[2] > 1 && rect[3] > 1
                next.elementRect = CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3])
            }
            next.currentTime = (message["t"] as? Double) ?? 0
            next.duration = (message["d"] as? Double) ?? 0
            next.isPaused = (message["paused"] as? Bool) ?? true
            next.readyState = (message["ready"] as? Int) ?? 0
            let vw = (message["vw"] as? Double) ?? 0
            let vh = (message["vh"] as? Double) ?? 0
            next.videoSize = CGSize(width: vw, height: vh)
            status = next
        case "error":
            let code = (message["code"] as? Int) ?? -1
            issue = Self.embedIssue(code: code, videoID: embedVideoID)
        default:
            break
        }
    }

    /// Fehlercodes laut YouTube IFrame Player API (onError).
    static func embedIssue(code: Int, videoID: String?) -> PlayerIssue {
        let message: String
        switch code {
        case 2: message = "Ungültige Video-ID oder Parameter."
        case 5: message = "Der HTML5-Player konnte das Video nicht abspielen."
        case 100: message = "Video nicht gefunden – entfernt oder privat."
        case 101, 150: message = "Der Rechteinhaber erlaubt keine eingebettete Wiedergabe."
        case 152, 153: message = "Der eingebettete Player wurde von YouTube abgelehnt (fehlende App-Identität/Referrer)."
        default: message = "Unbekannter Player-Fehler (\(code))."
        }
        var actions: [PlayerIssue.Action] = []
        if let videoID {
            actions.append(.openOnYouTube(YouTubeLink.video(id: videoID, start: nil).siteURL))
        }
        actions.append(.goHome)
        return PlayerIssue(title: "Video nicht abspielbar", message: message, actions: actions)
    }

    private func handleNavigationError(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain" && (nsError.code == 102 || nsError.code == 204) { return }
        issue = PlayerIssue(title: "Seite konnte nicht geladen werden",
                            message: nsError.localizedDescription,
                            actions: [.retry, .goHome])
    }

    /// Liest nur öffentliche DOM-Eigenschaften (Position, Größe) des sichtbaren Videos – keine Stream-URLs.
    static let statusScript = """
    (function () {
      if (window.__demonicStatus) { return; }
      window.__demonicStatus = true;
      function post(m) {
        try { window.webkit.messageHandlers.\(messageHandlerName).postMessage(m); } catch (e) {}
      }
      function largestVideo() {
        var best = null, area = 0;
        var videos = document.querySelectorAll('video');
        for (var i = 0; i < videos.length; i++) {
          var r = videos[i].getBoundingClientRect();
          var a = Math.max(0, r.width) * Math.max(0, r.height);
          if (a > area) { area = a; best = videos[i]; }
        }
        return best;
      }
      function report() {
        var m = { type: 'status' };
        if (window.__demonicEmbed) {
          var frame = document.getElementById('player');
          var p = window.__demonicPlayer;
          if (frame) {
            var fr = frame.getBoundingClientRect();
            m.rect = [fr.left, fr.top, fr.width, fr.height];
            m.vw = 16; m.vh = 9;
          }
          if (p && typeof p.getCurrentTime === 'function') {
            m.t = p.getCurrentTime() || 0;
            m.d = p.getDuration() || 0;
            m.paused = p.getPlayerState() !== 1;
            m.ready = 4;
          }
        } else {
          var v = largestVideo();
          if (v) {
            var r = v.getBoundingClientRect();
            m.rect = [r.left, r.top, r.width, r.height];
            m.t = v.currentTime || 0;
            m.d = isFinite(v.duration) ? v.duration : 0;
            m.paused = !!v.paused;
            m.ready = v.readyState;
            m.vw = v.videoWidth; m.vh = v.videoHeight;
          }
        }
        post(m);
      }
      setInterval(report, 400);
      report();
    })();
    """
}

// MARK: - WKNavigationDelegate / WKUIDelegate

extension PlayerController: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            return .cancel
        }
        // App-Links (youtube://, intent:// …) bleiben draußen; alles läuft in derselben WebView.
        if scheme == "file" {
            return Self.isBundleFile(url, bundleRoot: Bundle.main.resourceURL) ? .allow : .cancel
        }
        return ["http", "https", "about", "blob", "data"].contains(scheme) ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        handleNavigationError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        handleNavigationError(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        issue = PlayerIssue(title: "Webinhalt wurde beendet",
                            message: "iOS hat den Web-Prozess beendet. Die Seite kann neu geladen werden.",
                            actions: [.retry, .goHome])
    }

    /// Links mit target=_blank in derselben WebView öffnen – es gibt nur eine WebView.
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

/// Verhindert den Retain-Zyklus WKUserContentController → Handler → WebView.
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var target: PlayerController?

    init(target: PlayerController) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.handleScriptMessage(message.body)
    }
}
