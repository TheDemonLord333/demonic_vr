//
//  CalibrationView.swift
//  Demonic VR
//
//  Regler für Leinwandgröße, horizontalen Abstand, vertikale Position und
//  manuellen Ausschnitt. Werte werden sofort lokal gespeichert.
//

import SwiftUI

struct CalibrationControls: View {
    @Environment(AppModel.self) private var model
    var compact = false
    @State private var confirmReset = false

    var body: some View {
        let store = model.calibration
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            Text("Leinwand").font(.headline)
            SliderRow(title: "Leinwandgröße",
                      value: store.binding(\.screenScale),
                      range: CalibrationSettings.screenScaleRange,
                      identifier: "calibration.screenScale")
            SliderRow(title: "Horizontaler Abstand",
                      value: store.binding(\.horizontalSpacing),
                      range: CalibrationSettings.horizontalSpacingRange,
                      identifier: "calibration.spacing",
                      signed: true)
            SliderRow(title: "Vertikale Position",
                      value: store.binding(\.verticalOffset),
                      range: CalibrationSettings.verticalOffsetRange,
                      identifier: "calibration.vertical",
                      signed: true)

            Divider()

            Toggle("Manueller Ausschnitt", isOn: store.binding(\.cropEnabled))
                .font(.headline)
                .accessibilityIdentifier("calibration.cropEnabled")
            Text("Für Quellen mit Rand oder Letterbox, z. B. die Referenzszene oder ein YouTube-Video mit schwarzen Balken.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if store.settings.cropEnabled {
                SliderRow(title: "Links", value: store.binding(\.crop.x), range: 0...0.9, identifier: "calibration.crop.x")
                SliderRow(title: "Oben", value: store.binding(\.crop.y), range: 0...0.9, identifier: "calibration.crop.y")
                SliderRow(title: "Breite", value: store.binding(\.crop.width), range: NormalizedRect.minimumSize...1, identifier: "calibration.crop.width")
                SliderRow(title: "Höhe", value: store.binding(\.crop.height), range: NormalizedRect.minimumSize...1, identifier: "calibration.crop.height")
                HStack {
                    Button("Mitte 50 %") {
                        store.update { $0.crop = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5) }
                    }
                    Button("Voll") {
                        store.update { $0.crop = .full }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Label("Auf Standard zurücksetzen", systemImage: "arrow.counterclockwise")
            }
            .accessibilityIdentifier("calibration.reset")
            .confirmationDialog("Kalibrierung zurücksetzen?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Zurücksetzen", role: .destructive) { store.reset() }
                    .accessibilityIdentifier("calibration.reset.confirm")
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let identifier: String
    var signed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(formatted)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            Slider(value: $value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(formatted)
                .accessibilityIdentifier(identifier)
        }
    }

    private var formatted: String {
        let percent = Int((value * 100).rounded())
        return signed && percent > 0 ? "+\(percent) %" : "\(percent) %"
    }
}

/// Kalibrierung mit Vorschau der Referenzszene – als Seite in den Einstellungen nutzbar.
struct CalibrationPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StereoCinemaView(frame: model.reference.frame, settings: model.calibration.settings)
                    .aspectRatio(2.17, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("calibration.preview")
                Text("Vorschau mit einer lokalen Testszene. Die Werte gelten für „In VR ansehen“. Die endgültige Prüfung erfolgt in der Brille.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CalibrationControls()
            }
            .padding()
        }
        .navigationTitle("Kalibrierung")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.reference.start() }
        .onDisappear {
            if !model.isInCardboard { model.reference.stop() }
        }
    }
}

/// Eigenständige Kalibrierung als Sheet.
struct CalibrationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CalibrationPage()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                            .accessibilityIdentifier("sheet.done")
                    }
                }
        }
    }
}
