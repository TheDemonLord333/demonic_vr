//
//  SnapshotEngine.swift
//  Demonic VR
//
//  Nimmt Bilder der YouTube-WebView mit der öffentlichen WebKit-API
//  WKWebView.takeSnapshot(with:completionHandler:) auf. Es ist höchstens
//  ein Snapshot-Aufruf gleichzeitig offen. Die Aufnahme endet beim Verlassen
//  der Ansicht und sobald die App inaktiv wird oder in den Hintergrund geht.
//

import Foundation
import Observation
import QuartzCore
import UIKit
import WebKit

nonisolated struct SnapshotInfo: Equatable, Sendable {
    var duration: TimeInterval
    var pixelSize: CGSize
    var region: CaptureRegion
    var isNew: Bool
    var isBlack: Bool
    var meanLuma: Double
}

@Observable
final class SnapshotEngine {
    enum Mode: String, Equatable {
        case idle = "Bereit"
        case single = "Einzelbildtest"
        case liveTest = "Live-Test"
        case cardboard = "Cardboard"
    }

    /// Obergrenze der Abfragerate (Snapshots pro Sekunde).
    static let maximumRate: Double = 30

    private(set) var mode: Mode = .idle
    private(set) var latest: VideoFrame?
    private(set) var lastInfo: SnapshotInfo?
    private(set) var stats = FrameStatistics()
    private(set) var lastError: String?
    private(set) var openCalls = 0
    private(set) var maxOpenCalls = 0
    private(set) var liveTestDeadline: TimeInterval?
    var afterScreenUpdates = false
    /// Breite des aufgenommenen Bildes in Punkten (WKSnapshotConfiguration.snapshotWidth).
    var maxSnapshotWidth: Double = 480

    @ObservationIgnored private let player: PlayerController
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var previousFingerprint: FrameFingerprint?
    @ObservationIgnored private var sequence = 0
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []

    var isRunning: Bool { loopTask != nil }

    init(player: PlayerController) {
        self.player = player
        let center = NotificationCenter.default
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
            lifecycleObservers.append(token)
        }
    }

    // MARK: - Steuerung

    /// Einzelbildtest: genau ein Snapshot.
    func captureSingle() async {
        stop()
        mode = .single
        resetMeasurement()
        await captureOnce()
        if mode == .single { mode = .idle }
    }

    /// Zeitlich begrenzter Live-Test.
    func startLiveTest(duration: TimeInterval = 10) {
        startLoop(.liveTest, duration: duration)
    }

    /// Fortlaufende Aufnahme für die Cardboard-Ansicht (endet mit stop()).
    func startCardboardStream() {
        startLoop(.cardboard, duration: nil)
    }

    func stop() {
        generation += 1
        loopTask?.cancel()
        loopTask = nil
        liveTestDeadline = nil
        mode = .idle
    }

    /// Beendet nur Tests, nicht den Cardboard-Stream.
    func stopTests() {
        if mode == .liveTest || mode == .single { stop() }
    }

    // MARK: - Schleife

    private func resetMeasurement() {
        previousFingerprint = nil
        lastError = nil
        maxOpenCalls = openCalls
        stats = FrameStatistics(startedAt: CACurrentMediaTime())
    }

    private func startLoop(_ newMode: Mode, duration: TimeInterval?) {
        stop()
        mode = newMode
        resetMeasurement()
        let begin = CACurrentMediaTime()
        liveTestDeadline = duration.map { begin + $0 }
        let token = generation
        loopTask = Task { [weak self] in
            let minimumInterval = 1.0 / SnapshotEngine.maximumRate
            while !Task.isCancelled {
                guard let self, self.generation == token else { return }
                if let deadline = self.liveTestDeadline, CACurrentMediaTime() >= deadline { break }
                let started = CACurrentMediaTime()
                await self.captureOnce()
                let spent = CACurrentMediaTime() - started
                let pause = max(minimumInterval - spent, 0.002)
                try? await Task.sleep(for: .seconds(pause))
            }
            self?.loopFinished(token)
        }
    }

    private func loopFinished(_ token: Int) {
        guard token == generation else { return }
        loopTask = nil
        liveTestDeadline = nil
        mode = .idle
    }

    private func captureOnce() async {
        // Höchstens ein Snapshot-Aufruf gleichzeitig.
        guard openCalls == 0 else { return }
        let started = CACurrentMediaTime()
        guard let region = player.captureRegion() else {
            lastError = "WebView ist nicht sichtbar oder hat keine Größe."
            stats.recordError(at: started, duration: 0)
            return
        }
        guard let webView = player.webView else {
            lastError = "WebView ist noch nicht angezeigt."
            stats.recordError(at: started, duration: 0)
            return
        }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = region.rect
        configuration.afterScreenUpdates = afterScreenUpdates
        configuration.snapshotWidth = NSNumber(value: Double(min(region.rect.width, maxSnapshotWidth)))

        openCalls += 1
        maxOpenCalls = max(maxOpenCalls, openCalls)
        let result: Result<UIImage, Error> = await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, error in
                if let image {
                    continuation.resume(returning: .success(image))
                } else {
                    continuation.resume(returning: .failure(error ?? SnapshotError.noImage))
                }
            }
        }
        openCalls -= 1
        let finished = CACurrentMediaTime()
        let duration = finished - started

        switch result {
        case .failure(let error):
            lastError = error.localizedDescription
            stats.recordError(at: finished, duration: duration)
        case .success(let image):
            guard let cgImage = image.cgImage else {
                lastError = SnapshotError.noImage.localizedDescription
                stats.recordError(at: finished, duration: duration)
                return
            }
            let fingerprint = FrameFingerprint(image: cgImage)
            let isNew = fingerprint.map { $0.isNewFrame(comparedTo: previousFingerprint) } ?? true
            let isBlack = fingerprint?.isNearlyBlack ?? false
            if let fingerprint { previousFingerprint = fingerprint }
            stats.recordFrame(at: finished, duration: duration, isNew: isNew, isBlack: isBlack)
            lastInfo = SnapshotInfo(duration: duration,
                                    pixelSize: CGSize(width: cgImage.width, height: cgImage.height),
                                    region: region,
                                    isNew: isNew,
                                    isBlack: isBlack,
                                    meanLuma: fingerprint?.meanLuma ?? 0)
            if isNew || latest == nil {
                sequence += 1
                latest = VideoFrame(image: cgImage, sequence: sequence, timestamp: finished)
            }
        }
    }
}

nonisolated enum SnapshotError: LocalizedError {
    case noImage

    var errorDescription: String? {
        switch self {
        case .noImage: return "WebKit hat kein Bild geliefert."
        }
    }
}
