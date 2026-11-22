//
//  FrameAnalysis.swift
//  Demonic VR
//
//  Bildvergleich (neue vs. wiederholte Frames, Schwarzbilder), Statistik
//  für Snapshot-Tests sowie die Freigabelogik für den Cardboard-Modus.
//

import CoreGraphics
import Foundation

/// Ein Bild, das in beide Augen gezeichnet wird.
nonisolated struct VideoFrame: Equatable, @unchecked Sendable {
    let image: CGImage
    let sequence: Int
    let timestamp: TimeInterval

    var pixelSize: CGSize { CGSize(width: image.width, height: image.height) }

    static func == (lhs: VideoFrame, rhs: VideoFrame) -> Bool {
        lhs.sequence == rhs.sequence && lhs.timestamp == rhs.timestamp && lhs.image === rhs.image
    }
}

// MARK: - Fingerprint

/// Verkleinertes Graustufenbild zum Vergleich aufeinanderfolgender Frames.
nonisolated struct FrameFingerprint: Equatable, Sendable {
    static let width = 48
    static let height = 27

    let luma: [UInt8]

    init(luma: [UInt8]) {
        self.luma = luma
    }

    init?(image: CGImage) {
        let w = Self.width
        let h = Self.height
        var buffer = [UInt8](repeating: 0, count: w * h)
        let drawn = buffer.withUnsafeMutableBytes { pointer -> Bool in
            guard let context = CGContext(
                data: pointer.baseAddress,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        luma = buffer
    }

    var meanLuma: Double {
        guard !luma.isEmpty else { return 0 }
        return Double(luma.reduce(0) { $0 + Int($1) }) / Double(luma.count)
    }

    var maxLuma: UInt8 { luma.max() ?? 0 }

    /// Praktisch schwarzes Bild (z. B. geschützte oder nicht gerenderte Videoebene).
    var isNearlyBlack: Bool { meanLuma < 10 && maxLuma < 48 }

    /// Anzahl der Pixel, die sich um mindestens `threshold` Graustufen unterscheiden.
    func changedPixels(comparedTo other: FrameFingerprint, threshold: Int = 3) -> Int {
        guard other.luma.count == luma.count else { return luma.count }
        var count = 0
        for index in luma.indices where abs(Int(luma[index]) - Int(other.luma[index])) >= threshold {
            count += 1
        }
        return count
    }

    func meanAbsoluteDifference(to other: FrameFingerprint) -> Double {
        guard other.luma.count == luma.count, !luma.isEmpty else { return 255 }
        var total = 0
        for index in luma.indices {
            total += abs(Int(luma[index]) - Int(other.luma[index]))
        }
        return Double(total) / Double(luma.count)
    }

    /// Ein Frame gilt als neu, wenn sich sichtbar Pixel geändert haben.
    func isNewFrame(comparedTo previous: FrameFingerprint?) -> Bool {
        guard let previous else { return true }
        return changedPixels(comparedTo: previous) >= 2
    }
}

// MARK: - Statistik

nonisolated struct FrameStatistics: Equatable, Sendable {
    struct Event: Equatable, Sendable {
        var time: TimeInterval
        var isNew: Bool
        var isBlack: Bool
        var isError: Bool
    }

    struct WindowRates: Equatable, Sendable {
        var window: TimeInterval
        var delivered: Int
        var new: Int
        var black: Int
        var errors: Int

        var deliveredFPS: Double { window > 0 ? Double(delivered) / window : 0 }
        var newFPS: Double { window > 0 ? Double(new) / window : 0 }
        var blackRatio: Double { delivered > 0 ? Double(black) / Double(delivered) : 0 }
    }

    static let recentWindow: TimeInterval = 3

    private(set) var startedAt: TimeInterval?
    private(set) var lastEventAt: TimeInterval?
    private(set) var lastNewFrameAt: TimeInterval?
    private(set) var delivered = 0
    private(set) var newFrames = 0
    private(set) var repeatedFrames = 0
    private(set) var blackFrames = 0
    /// Neue Frames mit sichtbarem Inhalt (nicht schwarz).
    private(set) var newVisibleFrames = 0
    private(set) var errors = 0
    private(set) var lastDuration: TimeInterval = 0
    private(set) var maxDuration: TimeInterval = 0
    private(set) var totalDuration: TimeInterval = 0
    private(set) var recent: [Event] = []

    init() {}

    init(startedAt: TimeInterval) {
        self.startedAt = startedAt
    }

    var hasStarted: Bool { startedAt != nil }

    var averageDuration: TimeInterval {
        let samples = delivered + errors
        return samples > 0 ? totalDuration / Double(samples) : 0
    }

    mutating func recordFrame(at time: TimeInterval, duration: TimeInterval, isNew: Bool, isBlack: Bool) {
        if startedAt == nil { startedAt = time }
        delivered += 1
        if isNew {
            newFrames += 1
            if !isBlack { newVisibleFrames += 1 }
            lastNewFrameAt = time
        } else {
            repeatedFrames += 1
        }
        if isBlack { blackFrames += 1 }
        recordDuration(duration)
        append(Event(time: time, isNew: isNew, isBlack: isBlack, isError: false))
    }

    mutating func recordError(at time: TimeInterval, duration: TimeInterval) {
        if startedAt == nil { startedAt = time }
        errors += 1
        recordDuration(duration)
        append(Event(time: time, isNew: false, isBlack: false, isError: true))
    }

    private mutating func recordDuration(_ duration: TimeInterval) {
        lastDuration = duration
        maxDuration = max(maxDuration, duration)
        totalDuration += duration
    }

    private mutating func append(_ event: Event) {
        lastEventAt = event.time
        recent.append(event)
        let cutoff = event.time - Self.recentWindow
        if let firstValid = recent.firstIndex(where: { $0.time >= cutoff }), firstValid > 0 {
            recent.removeFirst(firstValid)
        }
    }

    func elapsed(at now: TimeInterval) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(now - startedAt, 0)
    }

    func deliveredFPS(at now: TimeInterval) -> Double {
        let e = elapsed(at: now)
        return e > 0.001 ? Double(delivered) / e : 0
    }

    func newFPS(at now: TimeInterval) -> Double {
        let e = elapsed(at: now)
        return e > 0.001 ? Double(newFrames) / e : 0
    }

    /// Raten im gleitenden Fenster der letzten Sekunden.
    func recentRates(at now: TimeInterval, window: TimeInterval = FrameStatistics.recentWindow) -> WindowRates {
        let effectiveWindow = min(window, elapsed(at: now))
        let cutoff = now - effectiveWindow
        var rates = WindowRates(window: effectiveWindow, delivered: 0, new: 0, black: 0, errors: 0)
        for event in recent where event.time >= cutoff && event.time <= now {
            if event.isError {
                rates.errors += 1
            } else {
                rates.delivered += 1
                if event.isNew { rates.new += 1 }
                if event.isBlack { rates.black += 1 }
            }
        }
        return rates
    }

    /// Bewegung im Ausschnitt: mindestens drei sichtbare neue Frames und mindestens
    /// 20 % der gelieferten Frames sind sichtbar neu (vereinzelte Wechsel zählen nicht).
    var detectedMotion: Bool {
        newVisibleFrames >= 3 && Double(newVisibleFrames) >= 0.2 * Double(delivered)
    }
}

// MARK: - Freigabe

nonisolated enum FrameHealth: Equatable, Sendable {
    case ok
    case warmingUp
    case noFrames
    case stalled(seconds: Double)
    case black
    case tooSlow(newFPS: Double)
    case failing(errors: Int)

    var isUsable: Bool { self == .ok }

    var message: String {
        switch self {
        case .ok:
            return "Laufend neue Frames – nutzbar."
        case .warmingUp:
            return "Messung läuft – warte auf genügend Frames …"
        case .noFrames:
            return "Keine Frames empfangen."
        case .stalled(let seconds):
            return String(format: "Bild eingefroren – seit %.1f s kein neuer Frame.", seconds)
        case .black:
            return "Schwarzes Bild – die Quelle liefert keine sichtbaren Videoframes."
        case .tooSlow(let fps):
            return String(format: "Zu wenige neue Frames (%.1f/s).", fps)
        case .failing(let errors):
            return "Snapshot-Fehler (\(errors) im Messfenster)."
        }
    }
}

nonisolated enum CardboardGate {
    static let minimumNewFPS = 8.0
    static let minimumObservation: TimeInterval = 2.0
    static let stallTolerance: TimeInterval = 1.5
    static let maximumBlackRatio = 0.5

    static func health(_ stats: FrameStatistics, at now: TimeInterval) -> FrameHealth {
        guard stats.hasStarted else { return .noFrames }
        let elapsed = stats.elapsed(at: now)
        let rates = stats.recentRates(at: now)

        if stats.delivered == 0 {
            if stats.errors > 0 && elapsed >= minimumObservation { return .failing(errors: stats.errors) }
            return elapsed < minimumObservation ? .warmingUp : .noFrames
        }
        if rates.delivered > 0, rates.blackRatio > maximumBlackRatio {
            return .black
        }
        if let lastNew = stats.lastNewFrameAt, now - lastNew > stallTolerance {
            return .stalled(seconds: now - lastNew)
        }
        if rates.errors > max(rates.delivered, 2) {
            return .failing(errors: rates.errors)
        }
        if elapsed < minimumObservation {
            return .warmingUp
        }
        if rates.newFPS < minimumNewFPS {
            return .tooSlow(newFPS: rates.newFPS)
        }
        return .ok
    }
}

// MARK: - Quellen und ihre Vorgaben

nonisolated enum FrameSourceKind: String, Equatable, Sendable {
    case reference
    case youtubeSite
    case youtubeEmbed
    /// Mitgeliefertes, selbst erzeugtes Testvideo in einem HTML-<video> der WebView.
    case localVideoTest
    case otherWeb
    case none

    var title: String {
        switch self {
        case .reference: return "Referenzszene (lokal)"
        case .youtubeSite: return "YouTube-Ansicht"
        case .youtubeEmbed: return "YouTube IFrame-Player"
        case .localVideoTest: return "Lokales Testvideo (HTML-<video>)"
        case .otherWeb: return "Andere Webseite"
        case .none: return "Keine Quelle"
        }
    }
}

nonisolated enum SourcePolicyVerdict: Equatable, Sendable {
    case allowed
    case needsAcknowledgement
    case notPermitted(String)
}

nonisolated enum SourcePolicy {
    /// Hinweis, der für YouTube bestätigt werden muss.
    static let youtubeAcknowledgement = """
    Experimentell: Die Wiedergabe läuft weiter im YouTube-Player der WebView (mit dessen Werbung, \
    Bedienelementen und dem einzigen Audiopfad). Cardboard zeigt nur Bildschirm-Snapshots dieser \
    Ansicht für die private Betrachtung. Es werden keine Stream-URLs gelesen, nichts gespeichert \
    und kein Kopierschutz umgangen. Ich nutze YouTube gemäß den YouTube-Nutzungsbedingungen.
    """

    static func evaluate(_ kind: FrameSourceKind, acknowledged: Bool) -> SourcePolicyVerdict {
        switch kind {
        case .reference, .localVideoTest:
            // Eigene, selbst erzeugte Inhalte ohne Vorgaben Dritter.
            return .allowed
        case .youtubeSite:
            return acknowledged ? .allowed : .needsAcknowledgement
        case .youtubeEmbed:
            return .notPermitted("Der eingebettete IFrame-Player darf laut YouTube-API-Richtlinien nicht verdeckt oder verändert werden. Öffne das Video in der normalen YouTube-Ansicht.")
        case .otherWeb:
            return .notPermitted("Nur YouTube und die lokale Referenzszene sind als Quellen vorgesehen.")
        case .none:
            return .notPermitted("Es ist keine Quelle geladen.")
        }
    }

    static func canEnterCardboard(kind: FrameSourceKind, acknowledged: Bool, health: FrameHealth) -> Bool {
        guard evaluate(kind, acknowledged: acknowledged) == .allowed else { return false }
        if kind == .reference { return true }
        return health.isUsable
    }
}
