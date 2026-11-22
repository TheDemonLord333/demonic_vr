//
//  ReferenceScene.swift
//  Demonic VR
//
//  Animierte lokale Referenzszene mit sichtbarem Framezähler. Damit lassen
//  sich Ausschnitt, Seitenverhältnis und Synchronität beider Augen ohne
//  YouTube prüfen. Optional werden Aussetzer (Pufferung) simuliert.
//

import Foundation
import Observation
import QuartzCore
import UIKit

@Observable
final class ReferenceScene {
    static let frameSize = CGSize(width: 960, height: 540)
    /// Szenentakt: Framenummer = Laufzeit × 60.
    static let sceneRate: Double = 60

    private(set) var frame: VideoFrame?
    private(set) var stats = FrameStatistics()
    private(set) var isRunning = false
    private(set) var isInSimulatedDropout = false
    var simulateDropouts = false

    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var startTime: CFTimeInterval = 0
    @ObservationIgnored private var lastRenderedFrame = -1
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []

    init() {
        for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification] {
            let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            }
            lifecycleObservers.append(token)
        }
    }

    func start() {
        stopTask?.cancel()
        stopTask = nil
        guard displayLink == nil else { return }
        let proxy = DisplayLinkProxy { [weak self] link in self?.tick(link) }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.fire(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        startTime = CACurrentMediaTime()
        lastRenderedFrame = -1
        stats = FrameStatistics(startedAt: startTime)
        isRunning = true
        renderFrame(number: 0, at: startTime)
    }

    /// Läuft für eine begrenzte Zeit (Live-Test der Referenzquelle).
    func start(for seconds: TimeInterval) {
        start()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        displayLink?.invalidate()
        displayLink = nil
        isRunning = false
        isInSimulatedDropout = false
    }

    /// Einzelbild ohne laufende Animation.
    func captureSingle() {
        let now = CACurrentMediaTime()
        stats = FrameStatistics(startedAt: now)
        let number = Int((now - startTime) * Self.sceneRate)
        renderFrame(number: max(number, 0), at: now)
    }

    private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let elapsed = now - startTime
        let number = Int(elapsed * Self.sceneRate)
        guard number != lastRenderedFrame else { return }

        // Simulierte Pufferung: alle 4 s für 0,8 s keine neuen Frames.
        let inDropout = simulateDropouts && elapsed.truncatingRemainder(dividingBy: 4) >= 3.2
        isInSimulatedDropout = inDropout
        if inDropout {
            lastRenderedFrame = number
            stats.recordFrame(at: now, duration: 0, isNew: false, isBlack: false)
            return
        }
        renderFrame(number: number, at: now)
    }

    private func renderFrame(number: Int, at time: TimeInterval) {
        let started = CACurrentMediaTime()
        guard let image = Self.render(frame: number) else {
            stats.recordError(at: time, duration: CACurrentMediaTime() - started)
            return
        }
        lastRenderedFrame = number
        frame = VideoFrame(image: image, sequence: number, timestamp: time)
        stats.recordFrame(at: time, duration: CACurrentMediaTime() - started, isNew: true, isBlack: false)
    }

    // MARK: - Zeichnen

    static func render(frame number: Int, size: CGSize = ReferenceScene.frameSize) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            let cg = context.cgContext
            let w = size.width
            let h = size.height
            let t = Double(number) / sceneRate
            let bounds = CGRect(origin: .zero, size: size)

            // Hintergrund
            UIColor(red: 0.07, green: 0.02, blue: 0.12, alpha: 1).setFill()
            cg.fill(bounds)

            // 10-%-Raster für Ausschnittsprüfung
            cg.setStrokeColor(UIColor(white: 1, alpha: 0.14).cgColor)
            cg.setLineWidth(1)
            for i in 1..<10 {
                let x = w * CGFloat(i) / 10
                let y = h * CGFloat(i) / 10
                cg.move(to: CGPoint(x: x, y: 0)); cg.addLine(to: CGPoint(x: x, y: h))
                cg.move(to: CGPoint(x: 0, y: y)); cg.addLine(to: CGPoint(x: w, y: y))
            }
            cg.strokePath()

            // Mittelkreuz
            cg.setStrokeColor(UIColor(white: 1, alpha: 0.5).cgColor)
            cg.setLineWidth(2)
            cg.move(to: CGPoint(x: w / 2 - 30, y: h / 2)); cg.addLine(to: CGPoint(x: w / 2 + 30, y: h / 2))
            cg.move(to: CGPoint(x: w / 2, y: h / 2 - 30)); cg.addLine(to: CGPoint(x: w / 2, y: h / 2 + 30))
            cg.strokePath()

            // Bildrand (16:9) und Ecken-Markierungen
            let accent = UIColor(red: 0.55, green: 1.0, blue: 0.2, alpha: 1)
            cg.setStrokeColor(accent.cgColor)
            cg.setLineWidth(6)
            cg.stroke(bounds.insetBy(dx: 3, dy: 3))
            let cornerFont = UIFont.monospacedSystemFont(ofSize: 22, weight: .bold)
            let cornerAttributes: [NSAttributedString.Key: Any] = [.font: cornerFont, .foregroundColor: accent]
            ("OL" as NSString).draw(at: CGPoint(x: 14, y: 10), withAttributes: cornerAttributes)
            ("OR" as NSString).draw(at: CGPoint(x: w - 46, y: 10), withAttributes: cornerAttributes)
            ("UL" as NSString).draw(at: CGPoint(x: 14, y: h - 38), withAttributes: cornerAttributes)
            ("UR" as NSString).draw(at: CGPoint(x: w - 46, y: h - 38), withAttributes: cornerAttributes)

            // Drehender Zeiger (1 Umdrehung / 2 s)
            let angle = t * .pi
            let radius = min(w, h) * 0.32
            cg.setStrokeColor(UIColor(red: 0.75, green: 0.35, blue: 1, alpha: 0.9).cgColor)
            cg.setLineWidth(5)
            cg.move(to: CGPoint(x: w / 2, y: h / 2))
            cg.addLine(to: CGPoint(x: w / 2 + CGFloat(cos(angle)) * radius, y: h / 2 + CGFloat(sin(angle)) * radius))
            cg.strokePath()

            // Bewegte Kugel
            let ballRadius = h * 0.07
            let bx = (CGFloat(sin(t * 1.3)) * 0.38 + 0.5) * w
            let by = (CGFloat(cos(t * 0.9)) * 0.30 + 0.5) * h
            cg.setFillColor(accent.cgColor)
            cg.fillEllipse(in: CGRect(x: bx - ballRadius, y: by - ballRadius, width: ballRadius * 2, height: ballRadius * 2))

            // Frame-Leiste: 60 Felder, das aktuelle Feld leuchtet (Synchronprüfung auf Frame-Ebene)
            let cells = 60
            let barY = h - 70
            let cellWidth = (w - 120) / CGFloat(cells)
            for i in 0..<cells {
                let rect = CGRect(x: 60 + CGFloat(i) * cellWidth, y: barY, width: cellWidth - 2, height: 18)
                let active = i == ((number % cells) + cells) % cells
                (active ? UIColor.white : UIColor(white: 1, alpha: 0.18)).setFill()
                cg.fill(rect)
            }

            // Framezähler
            let counterFont = UIFont.monospacedDigitSystemFont(ofSize: 64, weight: .heavy)
            let counter = String(format: "FRAME %06d", number) as NSString
            let counterAttributes: [NSAttributedString.Key: Any] = [.font: counterFont, .foregroundColor: UIColor.white]
            let counterSize = counter.size(withAttributes: counterAttributes)
            counter.draw(at: CGPoint(x: (w - counterSize.width) / 2, y: 40), withAttributes: counterAttributes)

            let detailFont = UIFont.monospacedDigitSystemFont(ofSize: 24, weight: .medium)
            let detail = String(format: "t = %.2f s  ·  Demonic VR Referenz  ·  16:9", t) as NSString
            let detailAttributes: [NSAttributedString.Key: Any] = [.font: detailFont, .foregroundColor: UIColor(white: 1, alpha: 0.75)]
            let detailSize = detail.size(withAttributes: detailAttributes)
            detail.draw(at: CGPoint(x: (w - detailSize.width) / 2, y: 118), withAttributes: detailAttributes)
        }
        return image.cgImage
    }
}

/// CADisplayLink hält sein Ziel stark; der Proxy hält die Szene nur schwach.
final class DisplayLinkProxy: NSObject {
    private let handler: (CADisplayLink) -> Void

    init(_ handler: @escaping (CADisplayLink) -> Void) {
        self.handler = handler
    }

    @objc func fire(_ link: CADisplayLink) {
        handler(link)
    }
}
