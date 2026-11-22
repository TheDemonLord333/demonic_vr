//
//  DiagnosticsView.swift
//  Demonic VR
//
//  Snapshot-Diagnose: Einzelbildtest und zeitlich begrenzter Live-Test mit
//  Vorschau, Snapshot-Dauer, gelieferten und tatsächlich neuen Frames pro
//  Sekunde, wiederholten Frames und Fehlern. Dient auch als Freigabe-Prüfung
//  für den experimentellen YouTube-Cardboard-Modus.
//

import CoreGraphics
import Foundation
import QuartzCore
import SwiftUI

struct DiagnosticsView: View {
    enum Purpose {
        case diagnostics
        case cardboardCheck
    }

    enum Source: String, CaseIterable, Identifiable {
        case youtube = "YouTube-WebView"
        case reference = "Referenzszene"
        var id: String { rawValue }
    }

    let purpose: Purpose

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var source: Source = .youtube

    static let liveTestDuration: TimeInterval = 10
    static let gateTestDuration: TimeInterval = 6

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                if purpose == .diagnostics {
                    Section {
                        Picker("Quelle", selection: $source) {
                            ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("diag.source")
                    }
                }

                Section("Vorschau") {
                    preview
                }

                Section("Tests") {
                    testControls
                }

                Section("Messwerte") {
                    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                        metrics(now: CACurrentMediaTime())
                    }
                }

                if source == .youtube {
                    Section("Sitzung") {
                        LabeledContent("WebView", value: model.player.webViewShortID)
                        LabeledContent("Seite", value: model.player.sourceKind.title)
                        LabeledContent("Position", value: model.player.status.hasVideo
                                       ? "\(TimeFormatter.clock(model.player.status.currentTime)) (\(model.player.status.isPaused ? "pausiert" : "läuft"))"
                                       : "kein Video erkannt")
                        if let report = model.continuity {
                            Text(report.summary)
                                .font(.caption)
                                .foregroundStyle(report.isContinuous ? DemonicTheme.accent : .orange)
                        }
                    }

                    gateSection(acknowledged: $model.youtubeCardboardAcknowledged)
                }
            }
            .navigationTitle(purpose == .cardboardCheck ? "Cardboard-Prüfung" : "Snapshot-Diagnose")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("sheet.done")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zum Player") {
                        model.player.issue = nil
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if purpose == .cardboardCheck {
                source = .youtube
                model.snapshot.startLiveTest(duration: Self.gateTestDuration)
            }
        }
        .onChange(of: source) { _, _ in
            stopAll()
        }
        .onDisappear {
            stopAll()
        }
    }

    // MARK: - Vorschau

    private var currentFrame: VideoFrame? {
        source == .youtube ? model.snapshot.latest : model.reference.frame
    }

    @ViewBuilder
    private var preview: some View {
        if let frame = currentFrame {
            let settings = model.calibration.settings
            VStack(alignment: .leading, spacing: 8) {
                Image(frame.image, scale: 1, label: Text("Snapshot-Vorschau"))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .overlay {
                        GeometryReader { proxy in
                            if settings.cropEnabled {
                                let c = settings.crop.clamped()
                                Rectangle()
                                    .stroke(DemonicTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                    .frame(width: proxy.size.width * c.width, height: proxy.size.height * c.height)
                                    .offset(x: proxy.size.width * c.x, y: proxy.size.height * c.y)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("diag.preview")
                Text("Bild \(frame.image.width) × \(frame.image.height) px · #\(frame.sequence)\(settings.cropEnabled ? " · gestrichelt = Ausschnitt" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Stereo-Ansicht (beide Augen, gleicher Frame):")
                    .font(.caption)
                StereoCinemaView(frame: frame, settings: settings)
                    .aspectRatio(2.17, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        } else {
            Text("Noch kein Bild. Starte einen Test.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Tests

    @ViewBuilder
    private var testControls: some View {
        switch source {
        case .youtube:
            Button {
                Task { await model.snapshot.captureSingle() }
            } label: {
                Label("Einzelbildtest", systemImage: "camera.viewfinder")
            }
            .disabled(model.snapshot.openCalls > 0)
            .accessibilityIdentifier("diag.single")

            Button {
                model.snapshot.startLiveTest(duration: Self.liveTestDuration)
            } label: {
                Label("Live-Test (\(Int(Self.liveTestDuration)) s)", systemImage: "record.circle")
            }
            .disabled(model.snapshot.isRunning)
            .accessibilityIdentifier("diag.live")

            Button(role: .destructive) {
                model.snapshot.stop()
            } label: {
                Label("Aufnahme stoppen", systemImage: "stop.circle")
            }
            .disabled(!model.snapshot.isRunning)
            .accessibilityIdentifier("diag.stop")

            Toggle("afterScreenUpdates", isOn: Binding(
                get: { model.snapshot.afterScreenUpdates },
                set: { model.snapshot.afterScreenUpdates = $0 }
            ))
            Picker("Snapshot-Breite", selection: Binding(
                get: { model.snapshot.maxSnapshotWidth },
                set: { model.snapshot.maxSnapshotWidth = $0 }
            )) {
                Text("320 pt").tag(320.0)
                Text("480 pt").tag(480.0)
                Text("640 pt").tag(640.0)
                Text("960 pt").tag(960.0)
            }
            Text("Tipp: Video in der YouTube-Ansicht starten, dann testen. Erfasst wird nur der sichtbare Videobereich.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .reference:
            Button {
                model.reference.captureSingle()
            } label: {
                Label("Einzelbild", systemImage: "camera.viewfinder")
            }
            .accessibilityIdentifier("diag.single")
            Button {
                model.reference.start(for: Self.liveTestDuration)
            } label: {
                Label("Live-Test (\(Int(Self.liveTestDuration)) s)", systemImage: "record.circle")
            }
            .disabled(model.reference.isRunning)
            .accessibilityIdentifier("diag.live")
            Button(role: .destructive) {
                model.reference.stop()
            } label: {
                Label("Stoppen", systemImage: "stop.circle")
            }
            .disabled(!model.reference.isRunning)
            Toggle("Aussetzer simulieren", isOn: Binding(
                get: { model.reference.simulateDropouts },
                set: { model.reference.simulateDropouts = $0 }
            ))
        }
    }

    // MARK: - Messwerte

    @ViewBuilder
    private func metrics(now: TimeInterval) -> some View {
        let stats = source == .youtube ? model.snapshot.stats : model.reference.stats
        let running = source == .youtube ? model.snapshot.isRunning : model.reference.isRunning
        let reference = running ? now : (stats.lastEventAt ?? now)
        let rates = stats.recentRates(at: reference)

        LabeledContent("Status", value: source == .youtube ? model.snapshot.mode.rawValue : (running ? "läuft" : "bereit"))
        if source == .youtube, let deadline = model.snapshot.liveTestDeadline {
            LabeledContent("Restzeit", value: String(format: "%.1f s", max(deadline - now, 0)))
        }
        LabeledContent("Laufzeit", value: String(format: "%.1f s", stats.elapsed(at: reference)))
        LabeledContent("Snapshot-Dauer (letzte / Ø / max)",
                       value: String(format: "%.1f / %.1f / %.1f ms",
                                     stats.lastDuration * 1000, stats.averageDuration * 1000, stats.maxDuration * 1000))
        LabeledContent("Geliefert", value: String(format: "%.1f fps (aktuell %.1f)",
                                                  stats.deliveredFPS(at: reference), rates.deliveredFPS))
            .accessibilityIdentifier("diag.deliveredFPS")
        LabeledContent("Tatsächlich neu", value: String(format: "%.1f fps (aktuell %.1f)",
                                                        stats.newFPS(at: reference), rates.newFPS))
            .accessibilityIdentifier("diag.newFPS")
        LabeledContent("Frames geliefert / neu", value: "\(stats.delivered) / \(stats.newFrames)")
        LabeledContent("Wiederholte Frames", value: "\(stats.repeatedFrames)")
            .accessibilityIdentifier("diag.repeated")
        LabeledContent("Schwarze Frames", value: "\(stats.blackFrames)")
        LabeledContent("Fehler", value: "\(stats.errors)")
            .accessibilityIdentifier("diag.errors")
        if source == .youtube {
            LabeledContent("Gleichzeitig offene Snapshots (max)", value: "\(model.snapshot.maxOpenCalls)")
            if let info = model.snapshot.lastInfo {
                LabeledContent("Erfasster Bereich", value: "\(info.region.source.rawValue) \(Self.describe(info.region.rect))")
                LabeledContent("Helligkeit Ø", value: String(format: "%.0f / 255", info.meanLuma))
            }
            if let error = model.snapshot.lastError {
                Text("Letzter Fehler: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        if stats.delivered > 0 {
            Label(stats.detectedMotion ? "Bewegung im Ausschnitt erkannt" : "Keine Bewegung im Ausschnitt – Video läuft? Bild schwarz?",
                  systemImage: stats.detectedMotion ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(stats.detectedMotion ? DemonicTheme.accent : .orange)
                .accessibilityIdentifier("diag.motion")
        }
    }

    // MARK: - Freigabe

    @ViewBuilder
    private func gateSection(acknowledged: Binding<Bool>) -> some View {
        Section {
            let policy = model.youtubePolicy
            switch policy {
            case .notPermitted(let reason):
                Label(reason, systemImage: "hand.raised.fill")
                    .foregroundStyle(.orange)
            case .allowed, .needsAcknowledgement:
                Text(SourcePolicy.youtubeAcknowledgement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Hinweise gelesen und bestätigt", isOn: acknowledged)
                    .accessibilityIdentifier("gate.acknowledge")
            }

            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let now = CACurrentMediaTime()
                let health = model.youtubeFrameHealth(now: now)
                let ready = model.canStartYouTubeCardboard(now: now)
                VStack(alignment: .leading, spacing: 8) {
                    Label(health.message, systemImage: health.isUsable ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                        .foregroundStyle(health.isUsable ? DemonicTheme.accent : .orange)
                    HStack {
                        Button("Erneut prüfen") {
                            model.snapshot.startLiveTest(duration: Self.gateTestDuration)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.snapshot.isRunning)
                        Button("Snapshot-Cardboard") {
                            model.startYouTubeCardboard()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!ready)
                        .accessibilityIdentifier("gate.start")
                    }

                    Divider()

                    let mirror = model.player.mirrorReadiness(acknowledged: model.youtubeCardboardAcknowledged)
                    Text("Spiegel-Modus (experimenteller Versuch): zeigt die echte WebView im linken Auge und lässt iOS die Ebene per CAReplicatorLayer ins rechte Auge duplizieren. Ob iOS die Videoebene der WebView dabei mitrepliziert, ist auf dem iPhone noch nicht bestätigt – auch nicht dadurch, dass Snapshots schwarz sind. Nach dem Start musst du in der Brille prüfen, ob beide Augen das laufende Video zeigen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(mirror.message, systemImage: mirror.ready ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                        .foregroundStyle(mirror.ready ? DemonicTheme.accent : .orange)
                    Button("Spiegel-Cardboard starten") {
                        model.startYouTubeMirrorCardboard()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!mirror.ready)
                    .accessibilityIdentifier("gate.startMirror")
                }
            }
        } header: {
            Text("Cardboard-Freigabe (experimentell)")
        } footer: {
            Text("Snapshot-Cardboard nur, wenn laufend neue, nicht schwarze Frames ankommen (≥ \(Int(CardboardGate.minimumNewFPS)) neue Frames/s). Spiegel-Cardboard nur, wenn in der YouTube-Ansicht ein Video läuft. Beide setzen die bestätigten Hinweise voraus. Der normale Player bleibt jederzeit erreichbar.")
        }
    }

    private func stopAll() {
        model.snapshot.stopTests()
        if !model.isInCardboard { model.reference.stop() }
    }

    private static func describe(_ rect: CGRect) -> String {
        String(format: "%.0f,%.0f %.0f×%.0f pt", rect.minX, rect.minY, rect.width, rect.height)
    }
}
