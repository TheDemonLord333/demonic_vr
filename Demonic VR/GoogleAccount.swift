//
//  GoogleAccount.swift
//  Demonic VR
//
//  Optionale Anmeldung mit dem offiziellen Google-OAuth-2.0-Ablauf für
//  native Apps (Autorisierungscode + PKCE) über ASWebAuthenticationSession.
//  Diese Sitzung ist vollständig von der WKWebView-Sitzung getrennt.
//  Die Client-ID kommt aus „GoogleOAuth.plist“ (nicht in Git, siehe README).
//  Refresh-Token und Zugangstoken liegen ausschließlich in der iOS-Keychain
//  (nur dieses Gerät) und im Arbeitsspeicher – nie in UserDefaults, Dateien,
//  Logs oder Diagnoseberichten. Kein Client-Secret in der App (öffentlicher
//  iOS-Client mit PKCE).
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

nonisolated enum GoogleAuthError: LocalizedError, Equatable {
    case notConfigured
    case invalidCallback
    case stateMismatch
    case tokenRequestFailed(String)
    case notSignedIn
    /// Vorübergehendes Netzwerkproblem – gespeicherte Anmeldung bleibt erhalten.
    case network(String)
    /// Refresh-Token ungültig, abgelaufen oder widerrufen – neue Anmeldung nötig.
    case sessionExpired
    /// API antwortet auch mit frisch erneuertem Token mit 401.
    case unauthorized
    /// Während der Token-Erneuerung abgemeldet.
    case signedOutDuringRefresh

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Google-Anmeldung ist nicht eingerichtet (GoogleOAuth.plist fehlt)."
        case .invalidCallback: return "Die Anmeldung wurde abgebrochen oder lieferte keinen Code."
        case .stateMismatch: return "Antwort der Anmeldung passt nicht zur Anfrage."
        case .tokenRequestFailed(let detail): return "Token-Anfrage fehlgeschlagen: \(detail)"
        case .notSignedIn: return "Nicht angemeldet."
        case .network: return "Keine Verbindung zu Google. Deine Anmeldung bleibt gespeichert – bitte später erneut versuchen."
        case .sessionExpired: return "Die Google-Anmeldung ist abgelaufen oder wurde widerrufen. Bitte neu anmelden."
        case .unauthorized: return "Google hat den Zugriff abgelehnt. Bitte neu anmelden."
        case .signedOutDuringRefresh: return "Abgemeldet."
        }
    }

    /// Fehler, bei denen die gespeicherte Anmeldung erhalten bleibt.
    var keepsCredentials: Bool {
        switch self {
        case .network, .tokenRequestFailed: return true
        default: return false
        }
    }

    /// Ordnet Netzwerkfehler ein: vorübergehende Verbindungsprobleme → `.network`.
    static func classify(_ error: Error) -> Error {
        guard let urlError = error as? URLError else { return error }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
             .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
             .callIsActive, .resourceUnavailable:
            return GoogleAuthError.network("URLError \(urlError.code.rawValue)")
        default:
            return error
        }
    }
}

/// Token-Antwort des Google-Token-Endpunkts.
nonisolated struct GoogleTokenResponse: Decodable, Equatable, Sendable {
    let access_token: String
    let expires_in: Double?
    let refresh_token: String?
    let scope: String?
}

/// Fehlerantwort des Token-Endpunkts (z. B. `invalid_grant`).
nonisolated struct GoogleTokenErrorResponse: Decodable, Sendable {
    let error: String
}

/// In der Keychain gespeicherte Anmeldung. Wird NIE in UserDefaults, Dateien,
/// Logs oder Diagnoseberichte geschrieben.
nonisolated struct GoogleStoredCredentials: Codable, Equatable, Sendable {
    var clientID: String
    var refreshToken: String?
    var accessToken: String?
    var expiresAt: Date?
    var scope: String?
}

// MARK: - Speicher und Transport (austauschbar für Tests)

protocol GoogleCredentialStore: AnyObject {
    func load() throws -> GoogleStoredCredentials?
    func save(_ credentials: GoogleStoredCredentials) throws
    func delete() throws
}

/// Keychain-Speicher (kSecClassGenericPassword, nur auf diesem Gerät, nach erster Entsperrung).
final class KeychainCredentialStore: GoogleCredentialStore {
    static let service = "me.thedemonlord333.Demonic-VR.google-oauth"
    private let account: String

    init(account: String = "youtube.readonly") {
        self.account = account
    }

    nonisolated enum KeychainError: Error, Equatable {
        case status(OSStatus)
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: account]
    }

    func load() throws -> GoogleStoredCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw KeychainError.status(status) }
        return try? JSONDecoder().decode(GoogleStoredCredentials.self, from: data)
    }

    func save(_ credentials: GoogleStoredCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}

/// Nur im Arbeitsspeicher (UI-Tests, Unit-Tests).
final class InMemoryCredentialStore: GoogleCredentialStore {
    var stored: GoogleStoredCredentials?
    var failSaves = false

    init(_ stored: GoogleStoredCredentials? = nil) {
        self.stored = stored
    }

    func load() throws -> GoogleStoredCredentials? { stored }

    func save(_ credentials: GoogleStoredCredentials) throws {
        if failSaves { throw KeychainCredentialStore.KeychainError.status(errSecIO) }
        stored = credentials
    }

    func delete() throws { stored = nil }
}

protocol GoogleHTTPTransport: AnyObject {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class URLSessionGoogleTransport: GoogleHTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

// MARK: - Sitzung

@Observable
final class GoogleAccountSession {
    nonisolated static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    nonisolated static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    nonisolated static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    /// Zugangstokens so lange vor Ablauf erneuern.
    nonisolated static let refreshMargin: TimeInterval = 60
    /// Kein Token, nur ein Merker (kein Geheimnis): Beim nächsten Login einmal Zustimmung anfordern,
    /// weil Google zuvor keinen Refresh-Token geliefert hat.
    nonisolated static let needsOfflineConsentKey = "demonicvr.google.needsOfflineConsent"

    let config: GoogleOAuthConfig?
    private(set) var isSignedIn = false
    private(set) var isWorking = false
    private(set) var errorMessage: String?
    /// Hinweis bei vorübergehenden Problemen (Anmeldung bleibt gespeichert).
    private(set) var noticeMessage: String?

    @ObservationIgnored private var credentials: GoogleStoredCredentials?
    @ObservationIgnored private var refreshTask: Task<String, Error>?
    /// Wird bei jeder Abmeldung erhöht – Ergebnisse älterer Erneuerungen werden verworfen.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let store: GoogleCredentialStore
    @ObservationIgnored private let transport: GoogleHTTPTransport
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var now: () -> Date = { Date() }

    init(config: GoogleOAuthConfig?,
         store: GoogleCredentialStore = KeychainCredentialStore(),
         transport: GoogleHTTPTransport = URLSessionGoogleTransport(),
         defaults: UserDefaults = .standard) {
        self.config = config
        self.store = store
        self.transport = transport
        self.defaults = defaults
        loadStoredCredentials()
    }

    /// Hat Google beim letzten Login keinen Refresh-Token geliefert?
    var needsOfflineConsent: Bool { defaults.bool(forKey: Self.needsOfflineConsentKey) }

    /// Es gibt einen Refresh-Token (Anmeldung übersteht Neustart und Ablauf des Zugangstokens).
    var hasRefreshToken: Bool { credentials?.refreshToken != nil }

    private func loadStoredCredentials() {
        guard let config else { return }
        guard let stored = try? store.load() else { return }
        // Anmeldung einer anderen Client-ID verwerfen (z. B. nach geänderter GoogleOAuth.plist).
        guard stored.clientID == config.clientID else {
            try? store.delete()
            return
        }
        credentials = stored
        isSignedIn = stored.refreshToken != nil || hasUsableAccessToken(stored)
    }

    private func hasUsableAccessToken(_ creds: GoogleStoredCredentials?) -> Bool {
        guard let creds, creds.accessToken != nil, let expiresAt = creds.expiresAt else { return false }
        return expiresAt > now().addingTimeInterval(Self.refreshMargin)
    }

    /// Beim App-Start: gespeicherte Sitzung prüfen und abgelaufene Zugangstokens erneuern.
    func restoreSession() async {
        guard credentials != nil else { return }
        do {
            _ = try await validAccessToken()
        } catch {
            // Hinweise/Bereinigung erledigt validAccessToken.
        }
    }

    // MARK: Zugangstoken

    /// Liefert ein gültiges Zugangstoken und erneuert es bei Bedarf automatisch.
    func validAccessToken() async throws -> String {
        guard let creds = credentials else { throw GoogleAuthError.notSignedIn }
        if hasUsableAccessToken(creds), let token = creds.accessToken {
            return token
        }
        guard creds.refreshToken != nil else {
            // Alte Anmeldung ohne Refresh-Token: nach Ablauf ist ein neuer Login nötig.
            clearLocalSession(message: GoogleAuthError.sessionExpired.localizedDescription)
            defaults.set(true, forKey: Self.needsOfflineConsentKey)
            throw GoogleAuthError.sessionExpired
        }
        return try await refreshAccessToken()
    }

    /// Erneuert das Zugangstoken. Parallele Aufrufe teilen sich EINE Anfrage.
    func refreshAccessToken() async throws -> String {
        if let running = refreshTask {
            return try await running.value
        }
        guard let config, let refreshToken = credentials?.refreshToken else {
            throw GoogleAuthError.notSignedIn
        }
        let startedGeneration = generation
        let task = Task { [weak self] () throws -> String in
            guard let self else { throw GoogleAuthError.signedOutDuringRefresh }
            return try await self.performRefresh(refreshToken: refreshToken, config: config, generation: startedGeneration)
        }
        refreshTask = task
        defer {
            if generation == startedGeneration { refreshTask = nil }
        }
        return try await task.value
    }

    private func performRefresh(refreshToken: String, config: GoogleOAuthConfig, generation startedGeneration: Int) async throws -> String {
        let request = Self.formRequest(Self.tokenEndpoint, [
            "client_id": config.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            guard generation == startedGeneration else { throw GoogleAuthError.signedOutDuringRefresh }
            noticeMessage = GoogleAuthError.network("").localizedDescription
            throw GoogleAuthError.classify(error)
        }
        // Während der Anfrage abgemeldet? Dann nichts übernehmen und nichts speichern.
        guard generation == startedGeneration else { throw GoogleAuthError.signedOutDuringRefresh }

        if (200..<300).contains(response.statusCode),
           let token = try? JSONDecoder().decode(GoogleTokenResponse.self, from: data) {
            apply(token, keepingRefreshToken: refreshToken, clientID: config.clientID)
            noticeMessage = nil
            return token.access_token
        }
        let code = (try? JSONDecoder().decode(GoogleTokenErrorResponse.self, from: data))?.error
        if code == "invalid_grant" {
            // Refresh-Token widerrufen, abgelaufen (z. B. 7 Tage im Testmodus) oder ungültig.
            clearLocalSession(message: GoogleAuthError.sessionExpired.localizedDescription)
            throw GoogleAuthError.sessionExpired
        }
        if response.statusCode >= 500 || response.statusCode == 429 {
            noticeMessage = GoogleAuthError.network("").localizedDescription
            throw GoogleAuthError.network("HTTP \(response.statusCode)")
        }
        // Andere Client-/Konfigurationsfehler: Anmeldung behalten, Fehler zeigen.
        let detail = code ?? "HTTP \(response.statusCode)"
        errorMessage = GoogleAuthError.tokenRequestFailed(detail).localizedDescription
        throw GoogleAuthError.tokenRequestFailed(detail)
    }

    private func apply(_ token: GoogleTokenResponse, keepingRefreshToken existing: String?, clientID: String) {
        var creds = credentials ?? GoogleStoredCredentials(clientID: clientID)
        creds.clientID = clientID
        creds.accessToken = token.access_token
        creds.expiresAt = now().addingTimeInterval(token.expires_in ?? 3600)
        // Liefert Google keinen neuen Refresh-Token, bleibt der vorhandene erhalten.
        creds.refreshToken = token.refresh_token ?? existing ?? creds.refreshToken
        creds.scope = token.scope ?? creds.scope
        credentials = creds
        isSignedIn = true
        errorMessage = nil
        do {
            try store.save(creds)
        } catch {
            noticeMessage = "Anmeldung konnte nicht dauerhaft gespeichert werden (Keychain). Sie gilt bis zum App-Ende."
        }
    }

    // MARK: Autorisierte API-Anfragen

    /// Führt eine API-Anfrage mit gültigem Token aus. Bei 401 wird höchstens EINMAL mit
    /// erneuertem Token wiederholt.
    func authorizedData(for buildRequest: (String) -> URLRequest) async throws -> Data {
        let token = try await validAccessToken()
        let (data, response) = try await sendAPI(buildRequest(token))
        guard response.statusCode == 401 else { return try checked(data, response) }

        guard hasRefreshToken else {
            clearLocalSession(message: GoogleAuthError.sessionExpired.localizedDescription)
            throw GoogleAuthError.sessionExpired
        }
        let fresh = try await refreshAccessToken()
        let (retryData, retryResponse) = try await sendAPI(buildRequest(fresh))
        if retryResponse.statusCode == 401 { throw GoogleAuthError.unauthorized }
        return try checked(retryData, retryResponse)
    }

    private func sendAPI(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch {
            noticeMessage = GoogleAuthError.network("").localizedDescription
            throw GoogleAuthError.classify(error)
        }
    }

    private func checked(_ data: Data, _ response: HTTPURLResponse) throws -> Data {
        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GoogleAuthError.tokenRequestFailed("YouTube Data API: HTTP \(response.statusCode) \(String(body.prefix(160)))")
        }
        noticeMessage = nil
        return data
    }

    // MARK: Anmelden

    /// Baut die Autorisierungs-URL (Code-Flow mit PKCE, ohne Client-Secret).
    nonisolated static func authorizationURL(config: GoogleOAuthConfig, challenge: String, state: String,
                                             requestConsent: Bool) -> URL? {
        var components = URLComponents(string: authorizationEndpoint)
        var items = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuthConfig.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        // Nur wenn zuvor kein Refresh-Token kam: einmalig Zustimmung erneut anfordern.
        if requestConsent {
            items.append(URLQueryItem(name: "prompt", value: "consent"))
        }
        components?.queryItems = items
        return components?.url
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
        guard let authURL = Self.authorizationURL(config: config, challenge: PKCE.challenge(for: verifier),
                                                  state: state, requestConsent: needsOfflineConsent) else { return }
        do {
            let callback = try await session.authenticate(using: authURL,
                                                          callbackURLScheme: config.redirectScheme,
                                                          preferredBrowserSession: .ephemeral)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard items.first(where: { $0.name == "state" })?.value == state else { throw GoogleAuthError.stateMismatch }
            guard let code = items.first(where: { $0.name == "code" })?.value else { throw GoogleAuthError.invalidCallback }
            try await completeSignIn(code: code, verifier: verifier)
        } catch {
            if let authError = error as? ASWebAuthenticationSessionError, authError.code == .canceledLogin {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    /// Tauscht den Autorisierungscode gegen Tokens und speichert die Anmeldung.
    func completeSignIn(code: String, verifier: String) async throws {
        guard let config else { throw GoogleAuthError.notConfigured }
        let startedGeneration = generation
        let request = Self.formRequest(Self.tokenEndpoint, [
            "client_id": config.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": config.redirectURI,
        ])
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw GoogleAuthError.classify(error)
        }
        guard generation == startedGeneration else { throw GoogleAuthError.signedOutDuringRefresh }
        guard (200..<300).contains(response.statusCode),
              let token = try? JSONDecoder().decode(GoogleTokenResponse.self, from: data) else {
            let code = (try? JSONDecoder().decode(GoogleTokenErrorResponse.self, from: data))?.error
            throw GoogleAuthError.tokenRequestFailed(code ?? "HTTP \(response.statusCode)")
        }
        // Bestehenden Refresh-Token derselben Client-ID behalten, falls Google keinen neuen liefert.
        let existing = credentials?.clientID == config.clientID ? credentials?.refreshToken : nil
        apply(token, keepingRefreshToken: existing, clientID: config.clientID)
        defaults.set(credentials?.refreshToken == nil, forKey: Self.needsOfflineConsentKey)
        noticeMessage = credentials?.refreshToken == nil
            ? "Google hat keinen Refresh-Token geliefert. Die Anmeldung gilt bis zum Ablauf des Zugangstokens; beim nächsten Login wird die Zustimmung einmal erneut abgefragt."
            : nil
    }

    // MARK: Abmelden

    /// Lokal abmelden: Tokens aus Arbeitsspeicher und Keychain löschen. Funktioniert ohne Internet.
    /// Eine laufende Erneuerung wird verworfen und kann die Sitzung nicht wiederherstellen.
    @discardableResult
    func signOutLocally() -> String? {
        let tokenToRevoke = credentials?.refreshToken ?? credentials?.accessToken
        clearLocalSession(message: nil)
        noticeMessage = nil
        return tokenToRevoke
    }

    /// Abmelden und – falls möglich – den Zugriff bei Google widerrufen.
    func signOut() async {
        guard let token = signOutLocally() else { return }
        let request = Self.formRequest(Self.revokeEndpoint, ["token": token])
        // Ohne Internet schlägt nur der Widerruf fehl; lokal ist bereits abgemeldet.
        _ = try? await transport.send(request)
    }

    private func clearLocalSession(message: String?) {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        credentials = nil
        isSignedIn = false
        try? store.delete()
        errorMessage = message
    }

    // MARK: Hilfen

    nonisolated static func formRequest(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(fields)
        return request
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
    /// Liefert Tokens (mit automatischer Erneuerung und einmaliger Wiederholung bei 401).
    let session: GoogleAccountSession

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
        let url = components.url!
        let data = try await session.authorizedData { token in
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            return request
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
