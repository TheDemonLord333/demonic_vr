//
//  AppModel.swift
//  Demonic VR
//
//  Zentraler Zustand: genau ein Player (eine WKWebView), Kalibrierung,
//  Snapshot-Engine, Referenzszene und optionale Google-Anmeldung.
//

import Foundation
import Observation
import QuartzCore
import SwiftUI

nonisolated enum CardboardSource: String, Equatable, Sendable {
    case reference
    /// YouTube über WebKit-Snapshots (Bildkopie, Diagnose möglich).
    case youtube
    /// YouTube über CAReplicatorLayer (keine Bildkopie, Ebene wird repliziert).
    case youtubeMirror
    /// Lokales Testvideo (HTML-<video>) über denselben Spiegel-Weg wie YouTube.
    case localVideoMirror

    var title: String {
        switch self {
        case .reference: return "Referenzszene (nativ)"
        case .youtube: return "YouTube · Snapshot (experimentell)"
        case .youtubeMirror: return "YouTube · Spiegel (experimentell)"
        case .localVideoMirror: return "Lokales Testvideo · Spiegel (Test)"
        }
    }

    /// Nutzt die echte WebView über MirrorCinemaView/CAReplicatorLayer.
    var isMirror: Bool { self == .youtubeMirror || self == .localVideoMirror }
}

nonisolated struct AppEnvironment: Sendable {
    var isUITest: Bool
    /// UI-Tests der Entwicklerfunktionen: Entwickleroptionen von Anfang an zeigen.
    var forceDeveloperOptions: Bool = false

    static var current: AppEnvironment {
        let arguments = ProcessInfo.processInfo.arguments
        return AppEnvironment(isUITest: arguments.contains("-DemonicUITest"),
                              forceDeveloperOptions: arguments.contains("-DemonicDevOptions"))
    }
}

/// Ergebnis von „In VR ansehen“.
nonisolated enum VRStartResult: Equatable, Sendable {
    case started
    case needsAcknowledgement
    case unavailable(String)
}

@Observable
final class AppModel {
    enum Screen: Equatable {
        case player
        case cardboard(CardboardSource)
    }

    enum Sheet: String, Identifiable {
        case diagnostics
        case cardboardCheck
        case calibration
        case playlists
        case mirrorTest
        case settings

        var id: String { rawValue }
    }

    static let developerOptionsKey = "demonicvr.showDeveloperOptions"
    static let youtubeAcknowledgedKey = "demonicvr.youtubeVRAcknowledged"
    /// Die auf dem iPhone erfolgreich getestete VR-Anordnung: zwei Replikate, Original verborgen.
    static let vrMirrorMode: MirrorDisplayMode = .twoReplicas

    let environment: AppEnvironment
    let player: PlayerController
    let calibration: CalibrationStore
    let snapshot: SnapshotEngine
    let reference: ReferenceScene
    let google: GoogleAccountSession
    let mirrorTest = MirrorTestSession()

    var screen: Screen = .player
    var sheet: Sheet?
    /// Bestätigung der YouTube-Hinweise (über „In VR ansehen“ dauerhaft gespeichert).
    var youtubeCardboardAcknowledged = false
    private(set) var continuity: ContinuityReport?
    /// Entwickler-/Diagnosefunktionen und technische Statusleiste auf der Hauptseite zeigen.
    private(set) var showDeveloperOptions = false
    /// Anordnung der laufenden Spiegel-Sitzung (VR: immer `vrMirrorMode`).
    private(set) var activeMirrorMode: MirrorDisplayMode = AppModel.vrMirrorMode
    /// Die laufende Spiegel-Sitzung kam aus dem Spiegeltest (zeigt Testhilfen in Cardboard).
    private(set) var activeMirrorIsTest = false

    @ObservationIgnored private var continuityStart: ContinuityMark?
    @ObservationIgnored private let defaults: UserDefaults

    init(environment: AppEnvironment = .current) {
        self.environment = environment
        let defaults: UserDefaults
        if environment.isUITest, let suite = UserDefaults(suiteName: "DemonicVR.UITests") {
            suite.removePersistentDomain(forName: "DemonicVR.UITests")
            defaults = suite
        } else {
            defaults = .standard
        }
        self.defaults = defaults
        self.showDeveloperOptions = environment.forceDeveloperOptions || defaults.bool(forKey: Self.developerOptionsKey)
        self.youtubeCardboardAcknowledged = defaults.bool(forKey: Self.youtubeAcknowledgedKey)
        let player = PlayerController(startURL: environment.isUITest ? nil : PlayerController.homeURL)
        self.player = player
        self.calibration = CalibrationStore(defaults: defaults)
        self.snapshot = SnapshotEngine(player: player)
        self.reference = ReferenceScene()
        // UI-Tests berühren die Keychain nicht.
        let credentialStore: GoogleCredentialStore = environment.isUITest ? InMemoryCredentialStore() : KeychainCredentialStore()
        self.google = GoogleAccountSession(config: GoogleOAuthConfig.load(), store: credentialStore, defaults: defaults)
    }

    var isInCardboard: Bool {
        if case .cardboard = screen { return true }
        return false
    }

    // MARK: - Freigabe YouTube-Cardboard

    var youtubePolicy: SourcePolicyVerdict {
        SourcePolicy.evaluate(player.sourceKind, acknowledged: youtubeCardboardAcknowledged)
    }

    /// Ergebnis der Frame-Prüfung. Läuft kein Test, zählt das Ende des letzten Tests (max. 30 s alt).
    func youtubeFrameHealth(now: TimeInterval = CACurrentMediaTime()) -> FrameHealth {
        let stats = snapshot.stats
        if snapshot.isRunning { return CardboardGate.health(stats, at: now) }
        guard let last = stats.lastEventAt, now - last < 30 else { return .noFrames }
        return CardboardGate.health(stats, at: last)
    }

    func canStartYouTubeCardboard(now: TimeInterval = CACurrentMediaTime()) -> Bool {
        SourcePolicy.canEnterCardboard(kind: player.sourceKind,
                                       acknowledged: youtubeCardboardAcknowledged,
                                       health: youtubeFrameHealth(now: now))
    }

    // MARK: - Einstellungen

    /// Blendet nur Bedienelemente ein/aus – WebView und Wiedergabe bleiben unberührt.
    func setShowDeveloperOptions(_ value: Bool) {
        showDeveloperOptions = value
        defaults.set(value, forKey: Self.developerOptionsKey)
    }

    func setYouTubeAcknowledged(_ value: Bool) {
        youtubeCardboardAcknowledged = value
        defaults.set(value, forKey: Self.youtubeAcknowledgedKey)
    }

    // MARK: - In VR ansehen

    /// Prüft, ob das aktuelle Video in VR gezeigt werden kann (Pause ist erlaubt).
    func vrAvailability(now: Date = Date()) -> (ready: Bool, message: String) {
        switch player.sourceKind {
        case .youtubeSite, .localVideoTest:
            break
        case .youtubeEmbed:
            return (false, "Der eingebettete IFrame-Player kann nicht in VR gezeigt werden. Öffne das Video in der YouTube-Ansicht (Menü „…“ → IFrame-Player aus).")
        default:
            return (false, "Öffne zuerst ein Video in der YouTube-Ansicht.")
        }
        let status = player.status
        guard status.hasVideo, now.timeIntervalSince(status.updatedAt) < 3 else {
            return (false, "Kein Video erkannt. Öffne ein Video und starte es kurz.")
        }
        return (true, "Bereit für VR.")
    }

    /// „In VR ansehen“: startet direkt die getestete Konfiguration (zwei Replikate,
    /// Original verborgen) mit derselben WebView – ohne Einstellungen im Spiegeltest.
    @discardableResult
    func startVR() -> VRStartResult {
        let availability = vrAvailability()
        guard availability.ready else { return .unavailable(availability.message) }
        let source: CardboardSource = player.sourceKind == .localVideoTest ? .localVideoMirror : .youtubeMirror
        if source == .youtubeMirror && !youtubeCardboardAcknowledged {
            return .needsAcknowledgement
        }
        snapshot.stop()
        sheet = nil
        enterCardboard(source, mirrorMode: Self.vrMirrorMode, fromTest: false)
        return .started
    }

    // MARK: - Ansichtswechsel

    func startReferenceCardboard() {
        sheet = nil
        enterCardboard(.reference)
    }

    func requestYouTubeCardboard() {
        sheet = .cardboardCheck
    }

    @discardableResult
    func startYouTubeMirrorCardboard() -> Bool {
        guard player.sourceKind == .youtubeSite,
              player.mirrorReadiness(acknowledged: youtubeCardboardAcknowledged).ready else { return false }
        snapshot.stop()
        sheet = nil
        enterCardboard(.youtubeMirror, mirrorMode: mirrorTest.mode, fromTest: true)
        return true
    }

    /// Lokaler Vergleichstest: dieselbe WebView, derselbe Spiegel-Weg, eigenes ungeschütztes Video.
    @discardableResult
    func startLocalVideoMirrorCardboard() -> Bool {
        guard player.sourceKind == .localVideoTest,
              player.mirrorReadiness(acknowledged: false).ready else { return false }
        snapshot.stop()
        sheet = nil
        enterCardboard(.localVideoMirror, mirrorMode: mirrorTest.mode, fromTest: true)
        return true
    }

    @discardableResult
    func startYouTubeCardboard() -> Bool {
        guard canStartYouTubeCardboard() else { return false }
        sheet = nil
        enterCardboard(.youtube)
        return true
    }

    private func enterCardboard(_ source: CardboardSource,
                                mirrorMode: MirrorDisplayMode = AppModel.vrMirrorMode,
                                fromTest: Bool = false) {
        continuityStart = player.continuityMark()
        continuity = nil
        if source.isMirror {
            activeMirrorMode = mirrorMode
            activeMirrorIsTest = fromTest
            player.mirrorPageSize = player.webView?.bounds.size
            player.mirrorSessionActive = true
            mirrorTest.begin(source: player.sourceKind,
                             mode: mirrorMode,
                             calibration: calibration.settings,
                             status: player.status,
                             webViewSize: player.webView?.bounds.size)
        }
        screen = .cardboard(source)
    }

    func exitCardboard(then nextSheet: Sheet? = nil) {
        snapshot.stop()
        reference.stop()
        if case .cardboard(let source) = screen, source.isMirror {
            mirrorTest.finish(status: player.status)
        }
        // Erst die Übernahme sperren, dann zurückgeben – sonst holt sich die noch
        // sichtbare Spiegel-Ansicht die WebView beim nächsten Update zurück.
        player.mirrorSessionActive = false
        player.returnWebViewHome()
        player.mirrorPageSize = nil
        screen = .player
        if let nextSheet { sheet = nextSheet }
        guard let start = continuityStart else { return }
        continuityStart = nil
        // Status der Seite wird alle 0,4 s gemeldet – kurz warten, dann vergleichen.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self else { return }
            self.continuity = ContinuityReport(before: start, after: self.player.continuityMark())
        }
    }

    func startFrameSource(_ source: CardboardSource) {
        switch source {
        case .reference: reference.start()
        case .youtube: snapshot.startCardboardStream()
        case .youtubeMirror, .localVideoMirror: break
        }
    }

    func stopFrameSource(_ source: CardboardSource) {
        switch source {
        case .reference: reference.stop()
        case .youtube: snapshot.stop()
        case .youtubeMirror, .localVideoMirror:
            player.mirrorSessionActive = false
            player.returnWebViewHome()
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if case .cardboard(let source) = screen { startFrameSource(source) }
        default:
            snapshot.stop()
            reference.stop()
        }
    }
}
