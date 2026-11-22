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
    /// YouTube über CAReplicatorLayer (keine Bildkopie, Ebene wird gespiegelt).
    case youtubeMirror

    var title: String {
        switch self {
        case .reference: return "Referenzszene"
        case .youtube: return "YouTube · Snapshot (experimentell)"
        case .youtubeMirror: return "YouTube · Spiegel (experimentell)"
        }
    }
}

nonisolated struct AppEnvironment: Sendable {
    var isUITest: Bool

    static var current: AppEnvironment {
        AppEnvironment(isUITest: ProcessInfo.processInfo.arguments.contains("-DemonicUITest"))
    }
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

        var id: String { rawValue }
    }

    let environment: AppEnvironment
    let player: PlayerController
    let calibration: CalibrationStore
    let snapshot: SnapshotEngine
    let reference: ReferenceScene
    let google: GoogleAccountSession

    var screen: Screen = .player
    var sheet: Sheet?
    /// Bestätigung der YouTube-Hinweise, nur für die laufende Sitzung.
    var youtubeCardboardAcknowledged = false
    private(set) var continuity: ContinuityReport?

    @ObservationIgnored private var continuityStart: ContinuityMark?

    init(environment: AppEnvironment = .current) {
        self.environment = environment
        let defaults: UserDefaults
        if environment.isUITest, let suite = UserDefaults(suiteName: "DemonicVR.UITests") {
            suite.removePersistentDomain(forName: "DemonicVR.UITests")
            defaults = suite
        } else {
            defaults = .standard
        }
        let player = PlayerController(startURL: environment.isUITest ? nil : PlayerController.homeURL)
        self.player = player
        self.calibration = CalibrationStore(defaults: defaults)
        self.snapshot = SnapshotEngine(player: player)
        self.reference = ReferenceScene()
        self.google = GoogleAccountSession(config: GoogleOAuthConfig.load())
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
        guard player.mirrorReadiness(acknowledged: youtubeCardboardAcknowledged).ready else { return false }
        snapshot.stop()
        sheet = nil
        enterCardboard(.youtubeMirror)
        return true
    }

    @discardableResult
    func startYouTubeCardboard() -> Bool {
        guard canStartYouTubeCardboard() else { return false }
        sheet = nil
        enterCardboard(.youtube)
        return true
    }

    private func enterCardboard(_ source: CardboardSource) {
        continuityStart = player.continuityMark()
        continuity = nil
        screen = .cardboard(source)
    }

    func exitCardboard(then nextSheet: Sheet? = nil) {
        snapshot.stop()
        reference.stop()
        player.returnWebViewHome()
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
        case .youtubeMirror: break
        }
    }

    func stopFrameSource(_ source: CardboardSource) {
        switch source {
        case .reference: reference.stop()
        case .youtube: snapshot.stop()
        case .youtubeMirror: player.returnWebViewHome()
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
