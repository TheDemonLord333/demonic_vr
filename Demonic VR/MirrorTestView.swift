//
//  MirrorTestView.swift
//  Demonic VR
//
//  Spiegel-Vergleichstest: lokales HTML-<video> und YouTube über denselben
//  MirrorCinemaView-/CAReplicatorLayer-Weg, die native Referenzszene als
//  dritter Vergleich, manuelle Sichtbeobachtungen je Bildschirmhälfte und
//  ein teilbarer Diagnosebericht.
//

import SwiftUI
import UIKit

struct MirrorTestView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        @Bindable var session = model.mirrorTest
        NavigationStack {
            Form {
                Section {
                    Text("1. Lokales Testvideo laden und im Spiegel öffnen. 2. In der Brille je Hälfte notieren, was zu sehen ist. 3. Dasselbe mit YouTube. 4. Bericht teilen.")
                        .font(.callout)
                    Text("Links/rechts sind die Bildschirmhälften im Querformat aus deiner Sicht. In Cardboard ist jede Hälfte beschriftet (Original-WebView oder Replikat).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Ablauf")
                }

                Section {
                    Picker("Anordnung", selection: $session.mode) {
                        ForEach(MirrorDisplayMode.allCases) { Text($0.title).tag($0) }
                    }
                    .accessibilityIdentifier("mirror.mode")
                    Text("„Original rechts“ trennt Bildschirmhälfte und Instanz. „Nur Original“ zeigt, ob die WebView ohne Replikation Video zeigt. „Zwei Replikate“ verbirgt das Original und zeigt Replikat 1 links, Replikat 2 rechts – damit lässt sich prüfen, ob das Video in jeder Replik oder nur in der zuletzt gezeichneten Instanz erscheint.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Darstellungsmodus (Spiegel)")
                }

                localSection
                youtubeSection

                Section {
                    Button {
                        model.startReferenceCardboard()
                    } label: {
                        Label("Native Referenzszene öffnen", systemImage: "square.grid.3x3.fill")
                    }
                    Text("Eigener Vergleich: lokal gezeichnete Bilder über die bisherige Stereo-Ansicht, ohne WebView und ohne Replikation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Referenz (nativ)")
                }

                observationSection
                reportSection
            }
            .navigationTitle("Spiegel-Vergleichstest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("sheet.done")
                }
            }
        }
    }

    // MARK: - Quellen

    private var localSection: some View {
        Section {
            Button {
                model.player.loadLocalMirrorTest()
            } label: {
                Label("Testseite in der WebView laden", systemImage: "film")
            }
            .accessibilityIdentifier("mirror.loadLocal")
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let isLocal = model.player.sourceKind == .localVideoTest
                let readiness = model.player.mirrorReadiness(acknowledged: false)
                VStack(alignment: .leading, spacing: 8) {
                    Label(isLocal ? readiness.message : "Testseite nicht geladen.",
                          systemImage: isLocal && readiness.ready ? "checkmark.circle.fill" : "clock")
                        .foregroundStyle(isLocal && readiness.ready ? DemonicTheme.accent : .orange)
                        .accessibilityIdentifier("mirror.localStatus")
                    Button {
                        model.startLocalVideoMirrorCardboard()
                    } label: {
                        Label("Spiegel starten – lokales Video", systemImage: "eyeglasses")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!(isLocal && readiness.ready))
                    .accessibilityIdentifier("mirror.startLocal")
                }
            }
        } header: {
            Text("Lokales Testvideo (HTML-<video>)")
        } footer: {
            Text("Selbst erzeugtes, ungeschütztes H.264-Video (Farbmuster, magenta Balken, eingebrannter Zähler „VIDEO-EBENE FRAME n“) in derselben WebView. Türkiser Rahmen, „HTML-OVERLAY“, roter Balken und „HTML ⏯“ sind HTML-Oberfläche. Die YouTube-Seite wird dafür verlassen; zurück über „YouTube“ oder „Zurück“.")
        }
    }

    private var youtubeSection: some View {
        Section {
            Button {
                model.player.goHome()
            } label: {
                Label("YouTube-Ansicht öffnen", systemImage: "house")
            }
            Toggle("YouTube-Hinweise bestätigt", isOn: Binding(
                get: { model.youtubeCardboardAcknowledged },
                set: { model.youtubeCardboardAcknowledged = $0 }
            ))
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                let isYouTube = model.player.sourceKind == .youtubeSite
                let readiness = model.player.mirrorReadiness(acknowledged: model.youtubeCardboardAcknowledged)
                VStack(alignment: .leading, spacing: 8) {
                    Label(isYouTube ? readiness.message : "YouTube-Ansicht nicht geladen.",
                          systemImage: isYouTube && readiness.ready ? "checkmark.circle.fill" : "clock")
                        .foregroundStyle(isYouTube && readiness.ready ? DemonicTheme.accent : .orange)
                    Button {
                        model.startYouTubeMirrorCardboard()
                    } label: {
                        Label("Spiegel starten – YouTube", systemImage: "eyeglasses")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!(isYouTube && readiness.ready))
                    .accessibilityIdentifier("mirror.startYouTube")
                }
            }
        } header: {
            Text("YouTube-Vergleich")
        } footer: {
            Text(SourcePolicy.youtubeAcknowledgement)
        }
    }

    // MARK: - Beobachtungen und Bericht

    private var observationSection: some View {
        Section {
            if model.mirrorTest.runs.isEmpty {
                Text("Noch kein Spiegel-Durchlauf.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(model.mirrorTest.runs.enumerated()), id: \.element.id) { index, run in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Durchlauf \(index + 1): \(run.source.title)")
                        .font(.subheadline.bold())
                    Text(run.mode.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    MirrorObservationColumn(run: run, leftHalf: true)
                    MirrorObservationColumn(run: run, leftHalf: false)
                    Text(MirrorDiagnosticReport.assessment(run))
                        .font(.caption)
                }
            }
            if !model.mirrorTest.runs.isEmpty {
                Button("Durchläufe löschen", role: .destructive) { model.mirrorTest.clear() }
            }
        } header: {
            Text("Manuelle Beobachtungen")
        } footer: {
            Text("Diese Angaben sind deine Sichtbefunde. Eine laufende Player-Zeit bestätigt keine sichtbare Videowiedergabe.")
        }
    }

    private var reportSection: some View {
        let report = model.mirrorTest.report(environment: ReportEnvironment.current)
        return Section {
            Text(report)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .accessibilityIdentifier("mirror.report")
            HStack {
                Button {
                    UIPasteboard.general.string = report
                    copied = true
                } label: {
                    Label(copied ? "Kopiert" : "Kopieren", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("mirror.copyReport")
                Spacer()
                ShareLink(item: report) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Diagnosebericht")
        } footer: {
            Text("Enthält App-/Build-Version, iOS-Version, Gerätetyp, Quelle, Anordnung, Kalibrierung, Geometrie und deine Beobachtungen – keine URLs, Cookies, Tokens oder Zugangsdaten.")
        }
    }
}
