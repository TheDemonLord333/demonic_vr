//
//  ContentView.swift
//  Demonic VR
//
//  Startansicht: „In VR ansehen“, YouTube in der einzigen WebView, Link-Eingabe,
//  YouTube/Zurück/Playlists. Einstellungen und Entwicklerfunktionen über „…“.
//  Die Cardboard-Ansicht liegt als Ebene darüber – die WebView bleibt immer
//  an derselben Stelle in der Hierarchie und wird nie neu erzeugt.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        ZStack {
            PlayerScreen()
            if case .cardboard(let source) = model.screen {
                CardboardView(source: source)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.screen)
        .sheet(item: $model.sheet) { sheet in
            sheetContent(sheet)
                .environment(model)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            model.handleScenePhase(phase)
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: AppModel.Sheet) -> some View {
        switch sheet {
        case .diagnostics:
            DiagnosticsView(purpose: .diagnostics)
        case .cardboardCheck:
            DiagnosticsView(purpose: .cardboardCheck)
        case .calibration:
            CalibrationSheet()
        case .playlists:
            PlaylistsView()
        case .mirrorTest:
            MirrorTestView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - Player

struct PlayerScreen: View {
    @Environment(AppModel.self) private var model
    @State private var linkText = ""
    @State private var vrConfirmationShown = false
    @FocusState private var linkFocused: Bool

    private let developerColumns = [GridItem(.adaptive(minimum: 100), spacing: 6)]

    var body: some View {
        // Die WebView steht an fester Position in diesem VStack. Ein-/Ausblenden der
        // Entwicklerzeilen ändert nur ihre Größe – sie wird weder neu erzeugt noch neu geladen.
        VStack(spacing: 0) {
            header
            vrButton
            linkBar
            navigationRow
            if model.showDeveloperOptions {
                developerGrid
            }
            if let issue = model.player.issue {
                IssueBanner(issue: issue) { action in
                    model.player.perform(action)
                }
            }
            WebViewHost(player: model.player)
                .background(Color.black)
            if model.showDeveloperOptions {
                statusBar
            }
        }
        .background(DemonicTheme.background.ignoresSafeArea())
        .alert("YouTube in VR (experimentell)", isPresented: $vrConfirmationShown) {
            Button("Bestätigen und in VR ansehen") {
                model.setYouTubeAcknowledged(true)
                startVR()
            }
            .accessibilityIdentifier("vr.confirm")
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(SourcePolicy.youtubeAcknowledgement)
        }
    }

    // MARK: Kopfzeile

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "eyeglasses")
                .font(.headline)
                .foregroundStyle(DemonicTheme.accent)
                .accessibilityHidden(true)
            Text("Demonic VR")
                .font(.headline.weight(.heavy))
                .foregroundStyle(.white)
                .accessibilityIdentifier("app.title")
            Spacer()
            if model.player.isLoading {
                ProgressView().controlSize(.small)
            }
            Menu {
                Button("Einstellungen", systemImage: "gearshape") {
                    linkFocused = false
                    model.sheet = .settings
                }
                .accessibilityIdentifier("menu.settings")
                Toggle("Links im IFrame-Player öffnen", isOn: Binding(
                    get: { model.player.preferEmbedPlayer },
                    set: { model.player.setPreferEmbedPlayer($0) }
                ))
                Button("Neu laden", systemImage: "arrow.clockwise") { model.player.reload() }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
            .accessibilityLabel("Weitere Optionen")
            .accessibilityIdentifier("menu.more")
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    // MARK: In VR ansehen

    private var vrButton: some View {
        Button(action: startVR) {
            Label("In VR ansehen", systemImage: "eyeglasses")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(DemonicTheme.accent)
        .foregroundStyle(.black)
        .controlSize(.large)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .accessibilityIdentifier("vr.start")
    }

    private func startVR() {
        linkFocused = false
        switch model.startVR() {
        case .started:
            break
        case .needsAcknowledgement:
            vrConfirmationShown = true
        case .unavailable(let message):
            model.player.issue = PlayerIssue(title: "VR gerade nicht möglich", message: message, actions: [.dismiss])
        }
    }

    // MARK: Link und Navigation

    private var linkBar: some View {
        HStack(spacing: 6) {
            TextField("YouTube-Link einfügen", text: $linkText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($linkFocused)
                .onSubmit(openLink)
                .accessibilityIdentifier("link.field")
            PasteButton(payloadType: String.self) { strings in
                let text = strings.first ?? ""
                Task { @MainActor in
                    linkText = text
                    openLink()
                }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.roundedRectangle)
            .controlSize(.small)
            Button("Öffnen", action: openLink)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(linkText.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("link.open")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private var navigationRow: some View {
        HStack(spacing: 6) {
            CompactChip(title: "YouTube", systemImage: "house.fill", identifier: "nav.home") {
                model.player.goHome()
            }
            CompactChip(title: "Zurück", systemImage: "chevron.backward", identifier: "nav.back") {
                model.player.goBack()
            }
            .disabled(!model.player.canGoBack)
            CompactChip(title: "Playlists", systemImage: "music.note.list", identifier: "nav.playlists") {
                model.sheet = .playlists
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    /// Entwickler-/Diagnosefunktionen – nur mit „Entwickleroptionen auf Hauptseite anzeigen“.
    private var developerGrid: some View {
        LazyVGrid(columns: developerColumns, spacing: 6) {
            CompactChip(title: "Spiegeltest", systemImage: "rectangle.split.2x1", identifier: "nav.mirrorTest") {
                linkFocused = false
                model.sheet = .mirrorTest
            }
            CompactChip(title: "Diagnose", systemImage: "waveform.path.ecg", identifier: "nav.diagnostics") {
                model.sheet = .diagnostics
            }
            CompactChip(title: "Referenz", systemImage: "square.grid.3x3.fill", identifier: "nav.reference") {
                linkFocused = false
                model.startReferenceCardboard()
            }
            CompactChip(title: "Snapshot β", systemImage: "camera.viewfinder", identifier: "nav.cardboard") {
                linkFocused = false
                model.requestYouTubeCardboard()
            }
            CompactChip(title: "Kalibrierung", systemImage: "slider.horizontal.3", identifier: "nav.calibration") {
                model.sheet = .calibration
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("developer.grid")
    }

    private var statusBar: some View {
        let status = model.player.status
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(model.player.sourceKind.title)
                if status.hasVideo {
                    Text("·")
                    Image(systemName: status.isPaused ? "pause.fill" : "play.fill")
                    Text("\(TimeFormatter.clock(status.currentTime)) / \(TimeFormatter.clock(status.duration))")
                        .monospacedDigit()
                }
                Spacer()
                Text("WebView \(model.player.webViewShortID)")
                    .foregroundStyle(.secondary)
            }
            if let report = model.continuity {
                Label(report.summary, systemImage: report.isContinuous ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(report.isContinuous ? DemonicTheme.accent : .orange)
                    .accessibilityIdentifier("player.continuity")
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(DemonicTheme.panel)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("developer.statusBar")
    }

    private func openLink() {
        linkFocused = false
        if model.player.open(input: linkText) {
            linkText = ""
        }
    }
}

/// Kompakter Knopf mit Symbol und kurzem Text im violetten Stil.
private struct CompactChip: View {
    let title: String
    let systemImage: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(DemonicTheme.violet)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

struct IssueBanner: View {
    let issue: PlayerIssue
    let perform: (PlayerIssue.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(issue.title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(issue.message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                ForEach(Array(issue.actions.enumerated()), id: \.offset) { _, action in
                    Button(action.title) { perform(action) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(action.identifier)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.issue")
    }
}

#Preview {
    ContentView()
        .environment(AppModel(environment: AppEnvironment(isUITest: true)))
}
