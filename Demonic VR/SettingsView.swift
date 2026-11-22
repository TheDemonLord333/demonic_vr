//
//  SettingsView.swift
//  Demonic VR
//
//  Einstellungen (über „…“ → „Einstellungen“): Kalibrierung, Wiedergabe-Optionen,
//  der Schalter für Entwickleroptionen und der Entwickler-/Diagnosebereich mit
//  Spiegeltest, Snapshot-Diagnose, Referenzszene und Testvideo.
//
//  Das Fenster ist ein normales Sheet über der Startansicht: Die eine WebView bleibt
//  darunter in der Hierarchie, Wiedergabe, Position, Sitzung und Ton laufen weiter.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        CalibrationPage()
                    } label: {
                        Label("Kalibrierung", systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("settings.calibration")
                } header: {
                    Text("VR")
                } footer: {
                    Text("„In VR ansehen“ zeigt das Video als zwei nebeneinanderliegende Leinwände. Leinwandgröße, Abstand und Position stellst du hier ein.")
                }

                Section {
                    Toggle("Links im IFrame-Player öffnen", isOn: Binding(
                        get: { model.player.preferEmbedPlayer },
                        set: { model.player.setPreferEmbedPlayer($0) }
                    ))
                    Toggle("YouTube-Hinweise für VR bestätigt", isOn: Binding(
                        get: { model.youtubeCardboardAcknowledged },
                        set: { model.setYouTubeAcknowledged($0) }
                    ))
                    .accessibilityIdentifier("settings.youtubeAck")
                } header: {
                    Text("Wiedergabe")
                } footer: {
                    Text("Der IFrame-Player lässt sich nicht in VR zeigen. Für VR Videos in der normalen YouTube-Ansicht öffnen.")
                }

                Section {
                    Toggle("Entwickleroptionen auf Hauptseite anzeigen", isOn: Binding(
                        get: { model.showDeveloperOptions },
                        set: { model.setShowDeveloperOptions($0) }
                    ))
                    .accessibilityIdentifier("settings.devOptions")
                } footer: {
                    Text("Blendet zusätzliche Test- und Diagnoseknöpfe sowie die technische Statusleiste auf der Hauptseite ein. Die Wiedergabe läuft dabei weiter.")
                }

                developerSection

                Section {
                    LabeledContent("Version", value: Self.versionText)
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("sheet.done")
                }
            }
        }
    }

    private var developerSection: some View {
        Section {
            Button {
                model.sheet = .mirrorTest
            } label: {
                Label("Spiegeltest (Original/Replikat, Seitenwechsel, Bericht)", systemImage: "rectangle.split.2x1")
            }
            .accessibilityIdentifier("settings.mirrorTest")
            Button {
                model.player.loadLocalMirrorTest()
                dismiss()
            } label: {
                Label("Lokales Testvideo laden", systemImage: "film")
            }
            Button {
                model.sheet = .diagnostics
            } label: {
                Label("Snapshot-Diagnose", systemImage: "waveform.path.ecg")
            }
            .accessibilityIdentifier("settings.diagnostics")
            Button {
                model.sheet = .cardboardCheck
            } label: {
                Label("Snapshot-Cardboard-Prüfung", systemImage: "eyeglasses")
            }
            Button {
                model.startReferenceCardboard()
            } label: {
                Label("Referenzszene (nativ)", systemImage: "square.grid.3x3.fill")
            }
            .accessibilityIdentifier("settings.reference")
            LabeledContent("WebView", value: model.player.webViewShortID)
            LabeledContent("Quelle", value: model.player.sourceKind.title)
        } header: {
            Text("Entwicklung & Diagnose")
        } footer: {
            Text("Diagnoseberichte und die Auswahl von Original/Replikat findest du im Spiegeltest.")
        }
    }

    static var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
