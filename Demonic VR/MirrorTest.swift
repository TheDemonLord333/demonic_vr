//
//  MirrorTest.swift
//  Demonic VR
//
//  Vergleichstest für den Spiegel-Modus: Durchläufe mit Quelle, Anordnung,
//  Kalibrierung und Geometrie sowie die MANUELLEN Sichtbeobachtungen des
//  Nutzers je Bildschirmhälfte. Daraus entsteht ein teilbarer Textbericht.
//  Der Bericht enthält keine URLs, Cookies, Tokens oder Zugangsdaten.
//

import Foundation
import Observation
import UIKit

/// Manuelle Beobachtung des Videobilds in einer Bildschirmhälfte.
nonisolated enum VideoObservation: String, CaseIterable, Identifiable, Codable, Sendable {
    case notRecorded
    case visibleMoving
    case visibleFrozen
    case black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notRecorded: return "nicht erfasst"
        case .visibleMoving: return "Videobild sichtbar und bewegt"
        case .visibleFrozen: return "Videobild sichtbar, aber eingefroren"
        case .black: return "Videobild schwarz"
        }
    }
}

/// Manuelle Beobachtung der HTML-Oberfläche/Bedienelemente in einer Bildschirmhälfte.
nonisolated enum OverlayObservation: String, CaseIterable, Identifiable, Codable, Sendable {
    case notRecorded
    case visible
    case notVisible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notRecorded: return "nicht erfasst"
        case .visible: return "HTML-Oberfläche/Bedienelemente sichtbar"
        case .notVisible: return "HTML-Oberfläche/Bedienelemente nicht sichtbar"
        }
    }
}

nonisolated struct HalfObservation: Equatable, Codable, Sendable {
    var video: VideoObservation = .notRecorded
    var overlay: OverlayObservation = .notRecorded

    var isRecorded: Bool { video != .notRecorded || overlay != .notRecorded }
}

nonisolated struct MirrorTestRun: Identifiable, Equatable, Sendable {
    let id = UUID()
    var startedAt: Date
    var endedAt: Date?
    var source: FrameSourceKind
    var mode: MirrorDisplayMode
    var calibration: CalibrationSettings
    var webViewSize: CGSize?
    var geometry: MirrorGeometry?
    var videoNaturalSize: CGSize
    var playerTimeStart: Double?
    var playerTimeEnd: Double?
    var left = HalfObservation()
    var right = HalfObservation()
}

/// Umgebungsdaten für den Bericht (ohne personenbezogene Daten).
nonisolated struct ReportEnvironment: Equatable, Sendable {
    var appVersion: String
    var build: String
    var systemName: String
    var systemVersion: String
    var deviceModel: String

    @MainActor static var current: ReportEnvironment {
        let info = Bundle.main.infoDictionary ?? [:]
        return ReportEnvironment(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "?",
            build: info["CFBundleVersion"] as? String ?? "?",
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion,
            deviceModel: Self.hardwareModel()
        )
    }

    /// Hardware-Kennung wie „iPhone18,1“ (im Simulator die simulierte Kennung).
    nonisolated static func hardwareModel() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        var info = utsname()
        uname(&info)
        let mirror = Mirror(reflecting: info.machine)
        let bytes = mirror.children.compactMap { $0.value as? Int8 }.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

nonisolated enum MirrorDiagnosticReport {
    static func make(runs: [MirrorTestRun], environment: ReportEnvironment, generatedAt: Date = Date()) -> String {
        var lines: [String] = []
        lines.append("Demonic VR – Spiegel-Diagnosebericht")
        lines.append("Erstellt: \(timestamp(generatedAt))")
        lines.append("App: Demonic VR \(environment.appVersion) (Build \(environment.build))")
        lines.append("System: \(environment.systemName) \(environment.systemVersion) · Gerät: \(environment.deviceModel)")
        lines.append("Hälften: LINKS/RECHTS = Bildschirmhälften im Querformat aus Sicht des Betrachters (wie in der App beschriftet).")
        lines.append("Hinweis: Sichtbefunde sind MANUELLE Beobachtungen. Eine laufende Player-Zeit bestätigt keine sichtbare Videowiedergabe.")
        if runs.isEmpty {
            lines.append("")
            lines.append("Noch kein Spiegel-Durchlauf.")
        }
        for (index, run) in runs.enumerated() {
            lines.append("")
            lines.append("Durchlauf \(index + 1) – \(timestamp(run.startedAt))")
            lines.append("  Testquelle: \(run.source.title)")
            lines.append("  Darstellungsmodus: Spiegel (CAReplicatorLayer) · \(run.mode.title)")
            lines.append("  Rolle LINKS: \(run.mode.role(leftHalf: true)) · Rolle RECHTS: \(run.mode.role(leftHalf: false))")
            let c = run.calibration
            lines.append(String(format: "  Kalibrierung: Größe %.0f %% · Abstand %+.0f %% · vertikal %+.0f %% · Ausschnitt %@",
                                c.screenScale * 100, c.horizontalSpacing * 100, c.verticalOffset * 100,
                                c.cropEnabled ? describe(c.crop) : "aus"))
            lines.append("  WebView-Größe: \(describe(run.webViewSize))")
            if let g = run.geometry {
                lines.append("  Container: \(describe(g.containerSize)) · Instanzen: \(g.instanceCount)")
                lines.append("  Erkanntes Videorechteck (Seite): \(g.videoRect.map { describe($0) } ?? "keins – ganze Seite")")
                lines.append("  Quellbereich nach Ausschnitt: \(describe(g.sourceRect))")
                if let second = g.secondReplicaRect {
                    lines.append("  Original (verborgen): \(describe(g.originalRect)) · Replikat 1: \(describe(g.replicaRect)) · Replikat 2: \(describe(second))")
                } else {
                    lines.append("  Sichtbar Original: \(describe(g.originalRect)) · Replikat: \(g.instanceCount > 1 ? describe(g.replicaRect) : "–")")
                }
            } else {
                lines.append("  Geometrie: nicht erfasst")
            }
            lines.append("  Video-Eigengröße (laut Seite): \(describe(run.videoNaturalSize))")
            lines.append("  Player-Zeit (nur Information): \(time(run.playerTimeStart)) → \(time(run.playerTimeEnd))")
            lines.append("  MANUELL LINKS:  Video: \(run.left.video.title) · Oberfläche: \(run.left.overlay.title)")
            lines.append("  MANUELL RECHTS: Video: \(run.right.video.title) · Oberfläche: \(run.right.overlay.title)")
            lines.append("  Einordnung: \(assessment(run))")
        }
        return lines.joined(separator: "\n")
    }

    /// Vorsichtige Einordnung – keine Ursachenbehauptung (insbesondere keine DRM-Diagnose).
    static func assessment(_ run: MirrorTestRun) -> String {
        // Ohne Replikat ist nur die linke Hälfte zu prüfen.
        if run.mode == .originalOnly {
            switch run.left.video {
            case .notRecorded: return "Sichtprüfung unvollständig (links)."
            case .visibleMoving: return "Original allein zeigt bewegtes Video."
            default: return "Original allein zeigt kein bewegtes Video – Problem schon ohne Replikation."
            }
        }
        guard run.left.video != .notRecorded, run.right.video != .notRecorded else {
            return "Sichtprüfung unvollständig."
        }
        let leftOK = run.left.video == .visibleMoving
        let rightOK = run.right.video == .visibleMoving
        if run.mode == .twoReplicas {
            if leftOK && rightOK { return "Video in beiden Replikaten bewegt sichtbar – Replikation ohne sichtbares Original funktioniert." }
            if !leftOK && !rightOK { return "Video in keinem Replikat bewegt sichtbar." }
            return rightOK
                ? "Video nur in Replikat 2 (rechts, zuletzt gezeichnete Instanz)."
                : "Video nur in Replikat 1 (links)."
        }
        if leftOK && rightOK { return "Video in beiden Hälften bewegt sichtbar." }
        if !leftOK && !rightOK { return "Video in keiner Hälfte bewegt sichtbar." }
        let videoHalfIsOriginal = leftOK == run.mode.originalIsLeft
        return "Video nur in einer Hälfte (\(leftOK ? "links" : "rechts")) – dort liegt die "
            + (videoHalfIsOriginal ? "Original-Instanz." : "replizierte Instanz.")
            + " Ursache damit nicht bestätigt; ein schwarzes Bild allein belegt keinen Inhaltsschutz."
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func time(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.1f s", value)
    }

    static func describe(_ size: CGSize?) -> String {
        guard let size else { return "–" }
        return String(format: "%.0f×%.0f pt", size.width, size.height)
    }

    static func describe(_ rect: CGRect) -> String {
        String(format: "x %.0f y %.0f · %.0f×%.0f", rect.minX, rect.minY, rect.width, rect.height)
    }

    static func describe(_ crop: NormalizedRect) -> String {
        String(format: "x %.2f y %.2f b %.2f h %.2f", crop.x, crop.y, crop.width, crop.height)
    }
}

@Observable
final class MirrorTestSession {
    var mode: MirrorDisplayMode = .originalLeft
    private(set) var runs: [MirrorTestRun] = []

    var currentRun: MirrorTestRun? { runs.last }

    func begin(source: FrameSourceKind, mode runMode: MirrorDisplayMode? = nil,
               calibration: CalibrationSettings, status: PlaybackStatus, webViewSize: CGSize?) {
        runs.append(MirrorTestRun(startedAt: Date(),
                                  source: source,
                                  mode: runMode ?? mode,
                                  calibration: calibration,
                                  webViewSize: webViewSize,
                                  videoNaturalSize: status.videoSize,
                                  playerTimeStart: status.hasVideo ? status.currentTime : nil))
    }

    func updateGeometry(_ geometry: MirrorGeometry) {
        guard !runs.isEmpty, runs[runs.count - 1].endedAt == nil else { return }
        runs[runs.count - 1].geometry = geometry
        runs[runs.count - 1].webViewSize = geometry.pageSize
    }

    func updateCalibration(_ calibration: CalibrationSettings) {
        guard !runs.isEmpty, runs[runs.count - 1].endedAt == nil else { return }
        runs[runs.count - 1].calibration = calibration
    }

    func finish(status: PlaybackStatus) {
        guard !runs.isEmpty, runs[runs.count - 1].endedAt == nil else { return }
        runs[runs.count - 1].endedAt = Date()
        runs[runs.count - 1].playerTimeEnd = status.hasVideo ? status.currentTime : nil
    }

    func setObservation(runID: UUID, leftHalf: Bool, video: VideoObservation? = nil, overlay: OverlayObservation? = nil) {
        guard let index = runs.firstIndex(where: { $0.id == runID }) else { return }
        if leftHalf {
            if let video { runs[index].left.video = video }
            if let overlay { runs[index].left.overlay = overlay }
        } else {
            if let video { runs[index].right.video = video }
            if let overlay { runs[index].right.overlay = overlay }
        }
    }

    func clear() {
        runs.removeAll()
    }

    func report(environment: ReportEnvironment) -> String {
        MirrorDiagnosticReport.make(runs: runs, environment: environment)
    }
}
