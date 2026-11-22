//
//  GoogleAccount.swift
//  Demonic VR
//
//  Optionale Anmeldung mit dem offiziellen Google-OAuth-2.0-Ablauf für
//  native Apps (Autorisierungscode + PKCE) über ASWebAuthenticationSession.
//  Diese Sitzung ist vollständig von der WKWebView-Sitzung getrennt.
//  Die Client-ID kommt aus „GoogleOAuth.plist“ (nicht in Git, siehe README);
//  Tokens werden nur im Arbeitsspeicher gehalten.
//

import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Security
import SwiftUI

nonisolated struct GoogleOAuthConfig: Equatable, Sendable {
    static let fileName = "GoogleOAuth"
    static let scope = "https://www.googleapis.com/auth/youtube.readonly"

    let clientID: String

    init?(clientID: String) {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(".apps.googleusercontent.com"),
              !trimmed.contains("YOUR_"), trimmed.count > 30 else { return nil }
        self.clientID = trimmed
    }

    /// iOS-Clients nutzen die umgekehrte Client-ID als URL-Schema.
    var redirectScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    static func load(bundle: Bundle = .main) -> GoogleOAuthConfig? {
        guard let url = bundle.url(forResource: fileName, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let clientID = plist["CLIENT_ID"] as? String else { return nil }
        return GoogleOAuthConfig(clientID: clientID)
    }
}

nonisolated enum PKCE {
    static func makeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            bytes = (0..<48).map { _ in UInt8.random(in: 0...255) }
        }
        return base64URL(Data(bytes))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

nonisolated enum GoogleAuthError: LocalizedError {
    case notConfigured
    case invalidCallback
    case stateMismatch
    case tokenRequestFailed(String)
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Google-Anmeldung ist nicht eingerichtet (GoogleOAuth.plist fehlt)."
        case .invalidCallback: return "Die Anmeldung wurde abgebrochen oder lieferte keinen Code."
        case .stateMismatch: return "Antwort der Anmeldung passt nicht zur Anfrage."
        case .tokenRequestFailed(let detail): return "Token-Anfrage fehlgeschlagen: \(detail)"
        case .notSignedIn: return "Nicht angemeldet."
        }
    }
}

private nonisolated struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Double?
}

@Observable
final class GoogleAccountSession {
    let config: GoogleOAuthConfig?
    private(set) var isSignedIn = false
    private(set) var isWorking = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var expiresAt: Date?

    init(config: GoogleOAuthConfig?) {
        self.config = config
    }

    func validAccessToken() throws -> String {
        guard let accessToken, let expiresAt, expiresAt > Date().addingTimeInterval(30) else {
            isSignedIn = false
            throw GoogleAuthError.notSignedIn
        }
        return accessToken
    }

    func signIn(using session: WebAuthenticationSession) async {
        guard let config else {
            errorMessage = GoogleAuthError.notConfigured.localizedDescription
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let verifier = PKCE.makeVerifier()
        let state = PKCE.makeVerifier()
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scope),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let authURL = components.url else { return }

        do {
            let callback = try await session.authenticate(using: authURL,
                                                          callbackURLScheme: config.redirectScheme,
                                                          preferredBrowserSession: .ephemeral)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard items.first(where: { $0.name == "state" })?.value == state else { throw GoogleAuthError.stateMismatch }
            guard let code = items.first(where: { $0.name == "code" })?.value else { throw GoogleAuthError.invalidCallback }
            let token = try await exchange(code: code, verifier: verifier, config: config)
            accessToken = token.access_token
            expiresAt = Date().addingTimeInterval(token.expires_in ?? 3600)
            isSignedIn = true
        } catch {
            if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func signOut() async {
        let token = accessToken
        accessToken = nil
        expiresAt = nil
        isSignedIn = false
        guard let token else { return }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(["token": token])
        _ = try? await URLSession.shared.data(for: request)
    }

    private func exchange(code: String, verifier: String, config: GoogleOAuthConfig) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody([
            "code": code,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GoogleAuthError.tokenRequestFailed(String(body.prefix(200)))
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    nonisolated static func formBody(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }
}

// MARK: - YouTube Data API v3

nonisolated struct YouTubePlaylist: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let itemCount: Int
}

nonisolated struct YouTubePlaylistEntry: Identifiable, Hashable, Sendable {
    let id: String
    let videoID: String
    let title: String
}

struct YouTubeDataClient {
    let accessToken: String

    private struct PlaylistResponse: Decodable {
        struct Item: Decodable {
            struct Snippet: Decodable { let title: String }
            struct Details: Decodable { let itemCount: Int? }
            let id: String
            let snippet: Snippet
            let contentDetails: Details?
        }
        let items: [Item]
        let nextPageToken: String?
    }

    private struct PlaylistItemsResponse: Decodable {
        struct Item: Decodable {
            struct Snippet: Decodable { let title: String }
            struct Details: Decodable { let videoId: String? }
            let id: String
            let snippet: Snippet
            let contentDetails: Details?
        }
        let items: [Item]
        let nextPageToken: String?
    }

    func myPlaylists() async throws -> [YouTubePlaylist] {
        var result: [YouTubePlaylist] = []
        var pageToken: String?
        repeat {
            var query = ["part": "snippet,contentDetails", "mine": "true", "maxResults": "50"]
            if let pageToken { query["pageToken"] = pageToken }
            let response: PlaylistResponse = try await get("playlists", query: query)
            result += response.items.map {
                YouTubePlaylist(id: $0.id, title: $0.snippet.title, itemCount: $0.contentDetails?.itemCount ?? 0)
            }
            pageToken = response.nextPageToken
        } while pageToken != nil && result.count < 200
        return result
    }

    func entries(in playlistID: String) async throws -> [YouTubePlaylistEntry] {
        var result: [YouTubePlaylistEntry] = []
        var pageToken: String?
        repeat {
            var query = ["part": "snippet,contentDetails", "playlistId": playlistID, "maxResults": "50"]
            if let pageToken { query["pageToken"] = pageToken }
            let response: PlaylistItemsResponse = try await get("playlistItems", query: query)
            result += response.items.compactMap { item in
                guard let videoID = item.contentDetails?.videoId, YouTubeLink.isValidVideoID(videoID) else { return nil }
                return YouTubePlaylistEntry(id: item.id, videoID: videoID, title: item.snippet.title)
            }
            pageToken = response.nextPageToken
        } while pageToken != nil && result.count < 500
        return result
    }

    private func get<T: Decodable>(_ resource: String, query: [String: String]) async throws -> T {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/\(resource)")!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GoogleAuthError.tokenRequestFailed("YouTube Data API: \(String(body.prefix(200)))")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
