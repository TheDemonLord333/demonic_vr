//
//  Calibration.swift
//  Demonic VR
//
//  Cardboard-Kalibrierung: Leinwandgröße, horizontaler Abstand, vertikale
//  Position und manueller Ausschnitt. Gespeichert lokal in UserDefaults.
//

import CoreGraphics
import Foundation
import Observation
import SwiftUI

/// Rechteck in normierten Koordinaten (0…1), Ursprung oben links.
nonisolated struct NormalizedRect: Codable, Equatable, Hashable, Sendable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 1
    var height: Double = 1

    static let full = NormalizedRect()
    static let minimumSize = 0.1

    var isFull: Bool {
        let c = clamped()
        return c.x <= 0.0001 && c.y <= 0.0001 && c.width >= 0.9999 && c.height >= 0.9999
    }

    func clamped() -> NormalizedRect {
        func finite(_ value: Double, _ fallback: Double) -> Double { value.isFinite ? value : fallback }
        var r = self
        r.width = min(max(finite(r.width, 1), Self.minimumSize), 1)
        r.height = min(max(finite(r.height, 1), Self.minimumSize), 1)
        r.x = min(max(finite(r.x, 0), 0), 1 - r.width)
        r.y = min(max(finite(r.y, 0), 0), 1 - r.height)
        return r
    }

    /// Pixelrechteck innerhalb eines Bildes der angegebenen Größe.
    func pixelRect(width imageWidth: Int, height imageHeight: Int) -> CGRect {
        let c = clamped()
        let w = Double(imageWidth)
        let h = Double(imageHeight)
        let rect = CGRect(x: c.x * w, y: c.y * h, width: c.width * w, height: c.height * h).integral
        return rect.intersection(CGRect(x: 0, y: 0, width: w, height: h))
    }
}

nonisolated struct CalibrationSettings: Codable, Equatable, Sendable {
    /// Anteil der Augenhälfte, den die Leinwand maximal einnimmt.
    var screenScale: Double = 0.9
    /// Zusätzlicher Abstand der beiden Leinwände (Anteil der Augenbreite, + = weiter auseinander).
    var horizontalSpacing: Double = 0
    /// Vertikale Verschiebung (Anteil der halben Höhe, + = nach unten).
    var verticalOffset: Double = 0
    var cropEnabled: Bool = false
    var crop: NormalizedRect = .full

    static let `default` = CalibrationSettings()

    static let screenScaleRange: ClosedRange<Double> = 0.4...1.0
    static let horizontalSpacingRange: ClosedRange<Double> = -0.25...0.25
    static let verticalOffsetRange: ClosedRange<Double> = -0.5...0.5

    func clamped() -> CalibrationSettings {
        func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            guard value.isFinite else { return fallback }
            return min(max(value, range.lowerBound), range.upperBound)
        }
        var s = self
        s.screenScale = clamp(s.screenScale, Self.screenScaleRange, 0.9)
        s.horizontalSpacing = clamp(s.horizontalSpacing, Self.horizontalSpacingRange, 0)
        s.verticalOffset = clamp(s.verticalOffset, Self.verticalOffsetRange, 0)
        s.crop = s.crop.clamped()
        return s
    }

    /// Effektiver Ausschnitt (voll, wenn der manuelle Ausschnitt aus ist).
    var effectiveCrop: NormalizedRect {
        cropEnabled ? crop.clamped() : .full
    }
}

@Observable
final class CalibrationStore {
    static let defaultsKey = "demonicvr.calibration.v1"

    private(set) var settings: CalibrationSettings

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    init(defaults: UserDefaults = .standard, key: String = "demonicvr.calibration.v1") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(CalibrationSettings.self, from: data) {
            settings = decoded.clamped()
        } else {
            settings = .default
        }
    }

    func update(_ change: (inout CalibrationSettings) -> Void) {
        var next = settings
        change(&next)
        next = next.clamped()
        guard next != settings else { return }
        settings = next
        persist()
    }

    func reset() {
        settings = .default
        defaults.removeObject(forKey: key)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }

    func binding<Value>(_ keyPath: WritableKeyPath<CalibrationSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in self.update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
