//
//  ContentView.swift
//  Demonic VR
//
//  Startansicht: YouTube in der einzigen WebView, Link-Eingabe und Zugang
//  zu Cardboard, Referenzszene, Diagnose, Kalibrierung und Playlists.
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
        }
    }
}

// MARK: - Player

struct PlayerScreen: View {
    @Environment(AppModel.self) private var model
    @State private var linkText = ""
    @FocusState private var linkFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            header
            linkBar
            actionGrid
            if let issue = model.player.issue {
                IssueBanner(issue: issue) { action in
                    model.player.perform(action)
                }
            }
            WebViewHost(webView: model.player.webView)
                .background(Color.black)
            statusBar
        }
        .background(DemonicTheme.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "eyeglasses")
                .font(.title2)
                .foregroundStyle(DemonicTheme.accent)
                .accessibilityHidden(true)
            Text("Demonic VR")
                .font(.title2.weight(.heavy))
                .foregroundStyle(.white)
                .accessibilityIdentifier("app.title")
            Spacer()
            if model.player.isLoading {
                ProgressView().controlSize(.small)
            }
            Menu {
                Toggle("Links im IFrame-Player öffnen", isOn: Binding(
                    get: { model.player.preferEmbedPlayer },
                    set: { model.player.setPreferEmbedPlayer($0) }
                ))
                Button("Neu laden", systemImage: "arrow.clockwise") { model.player.reload() }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3)
            }
            .accessibilityLabel("Weitere Optionen")
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var linkBar: some View {
        HStack(spacing: 8) {
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
            Button("Öffnen", action: openLink)
                .buttonStyle(.borderedProminent)
                .disabled(linkText.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("link.open")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private var actionGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ActionTile(title: "YouTube", systemImage: "house.fill", identifier: "nav.home") {
                model.player.goHome()
            }
            ActionTile(title: "Zurück", systemImage: "chevron.backward", identifier: "nav.back") {
                model.player.goBack()
            }
            .disabled(!model.player.canGoBack)
            ActionTile(title: "Cardboard", systemImage: "eyeglasses", identifier: "nav.cardboard", badge: "β") {
                linkFocused = false
                model.requestYouTubeCardboard()
            }
            ActionTile(title: "Referenz", systemImage: "square.grid.3x3.fill", identifier: "nav.reference") {
                linkFocused = false
                model.startReferenceCardboard()
            }
            ActionTile(title: "Diagnose", systemImage: "waveform.path.ecg", identifier: "nav.diagnostics") {
                model.sheet = .diagnostics
            }
            ActionTile(title: "Kalibrierung", systemImage: "slider.horizontal.3", identifier: "nav.calibration") {
                model.sheet = .calibration
            }
            ActionTile(title: "Playlists", systemImage: "music.note.list", identifier: "nav.playlists") {
                model.sheet = .playlists
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
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
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(DemonicTheme.panel)
    }

    private func openLink() {
        linkFocused = false
        if model.player.open(input: linkText) {
            linkText = ""
        }
    }
}

private struct ActionTile: View {
    let title: String
    let systemImage: String
    let identifier: String
    var badge: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .overlay(alignment: .topTrailing) {
                        if let badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .foregroundStyle(.black)
                                .padding(.horizontal, 3)
                                .background(DemonicTheme.accent, in: Capsule())
                                .offset(x: 10, y: -6)
                        }
                    }
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
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
