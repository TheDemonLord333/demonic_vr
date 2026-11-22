//
//  PlaylistsView.swift
//  Demonic VR
//
//  Optionale Playlist-Ansicht über offiziellen Google-Login und die
//  YouTube Data API. Die Grundfunktionen der App brauchen keine Anmeldung.
//  Ein gewähltes Video wird in der einen WebView geöffnet.
//

import AuthenticationServices
import Foundation
import SwiftUI

struct PlaylistsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.dismiss) private var dismiss

    @State private var playlists: [YouTubePlaylist] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Meine Playlists")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: YouTubePlaylist.self) { playlist in
                    PlaylistEntriesView(playlist: playlist)
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fertig") { dismiss() }
                            .accessibilityIdentifier("sheet.done")
                    }
                    if model.google.isSignedIn {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Abmelden") {
                                Task {
                                    await model.google.signOut()
                                    playlists = []
                                }
                            }
                        }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.google.config == nil {
            setupHint
        } else if !model.google.isSignedIn {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 48))
                    .foregroundStyle(DemonicTheme.accent)
                Text("Für die Playlist-Ansicht mit Google anmelden. Diese Anmeldung ist getrennt von der YouTube-Sitzung im Player.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button {
                    Task {
                        await model.google.signIn(using: webAuthenticationSession)
                        if model.google.isSignedIn { await load() }
                    }
                } label: {
                    Label("Mit Google anmelden", systemImage: "person.badge.key")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.google.isWorking)
                if let message = model.google.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
            .padding()
        } else {
            List {
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                }
                ForEach(playlists) { playlist in
                    NavigationLink(value: playlist) {
                        VStack(alignment: .leading) {
                            Text(playlist.title)
                            Text("\(playlist.itemCount) Videos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if isLoading { ProgressView() }
                else if playlists.isEmpty && errorText == nil {
                    ContentUnavailableView("Keine Playlists", systemImage: "music.note.list")
                }
            }
            .refreshable { await load() }
            .task { if playlists.isEmpty { await load() } }
        }
    }

    private var setupHint: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Optional – nicht eingerichtet", systemImage: "gearshape.2")
                    .font(.headline)
                Text("Die Playlist-Ansicht nutzt den offiziellen Google-Login (OAuth 2.0 mit PKCE) und die YouTube Data API v3. Für den normalen Player ist das nicht nötig.")
                Text("Einrichtung: In der Google Cloud Console eine OAuth-Client-ID vom Typ „iOS“ für die Bundle-ID me.thedemonlord333.Demonic-VR anlegen, die YouTube Data API v3 aktivieren und „Config/GoogleOAuth.example.plist“ als „Demonic VR/GoogleOAuth.plist“ mit der eigenen CLIENT_ID kopieren. Die Datei ist per .gitignore von Git ausgeschlossen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let token = try model.google.validAccessToken()
            playlists = try await YouTubeDataClient(accessToken: token).myPlaylists()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private struct PlaylistEntriesView: View {
    let playlist: YouTubePlaylist
    @Environment(AppModel.self) private var model
    @State private var entries: [YouTubePlaylistEntry] = []
    @State private var errorText: String?
    @State private var isLoading = false

    var body: some View {
        List {
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
            ForEach(entries) { entry in
                Button {
                    model.player.open(.video(id: entry.videoID, start: nil))
                    model.sheet = nil
                } label: {
                    Label(entry.title, systemImage: "play.rectangle")
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .navigationTitle(playlist.title)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let token = try model.google.validAccessToken()
            entries = try await YouTubeDataClient(accessToken: token).entries(in: playlist.id)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
