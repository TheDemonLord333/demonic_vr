//
//  YouTubeLink.swift
//  Demonic VR
//
//  Erkennt YouTube-Links (Video, Shorts, Live, Embed, youtu.be, Playlist,
//  sonstige YouTube-Seiten) und erzeugt daraus eine URL für die normale
//  mobile YouTube-Ansicht. Es werden nur öffentliche Seiten-URLs gebildet,
//  niemals Stream-URLs.
//

import Foundation

nonisolated enum YouTubeLink: Equatable, Hashable, Sendable {
    case video(id: String, start: Int?)
    case playlist(id: String)
    case page(URL)

    static let siteHost = "m.youtube.com"

    var videoID: String? {
        if case .video(let id, _) = self { return id }
        return nil
    }

    var startSeconds: Int? {
        if case .video(_, let start) = self { return start }
        return nil
    }

    /// URL für die normale YouTube-Ansicht in der WebView.
    var siteURL: URL {
        switch self {
        case .video(let id, let start):
            var components = URLComponents()
            components.scheme = "https"
            components.host = Self.siteHost
            components.path = "/watch"
            var items = [URLQueryItem(name: "v", value: id)]
            if let start, start > 0 {
                items.append(URLQueryItem(name: "t", value: "\(start)s"))
            }
            components.queryItems = items
            return components.url ?? URL(string: "https://\(Self.siteHost)/")!
        case .playlist(let id):
            var components = URLComponents()
            components.scheme = "https"
            components.host = Self.siteHost
            components.path = "/playlist"
            components.queryItems = [URLQueryItem(name: "list", value: id)]
            return components.url ?? URL(string: "https://\(Self.siteHost)/")!
        case .page(let url):
            return url
        }
    }

    // MARK: - Parsing

    static func parse(_ input: String) -> YouTubeLink? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isValidVideoID(trimmed) {
            return .video(id: trimmed, start: nil)
        }
        for token in trimmed.split(whereSeparator: { $0.isWhitespace }) {
            if let link = parseURLString(String(token)) {
                return link
            }
        }
        return nil
    }

    static func isValidVideoID<S: StringProtocol>(_ value: S) -> Bool {
        value.count == 11 && value.allSatisfy(isIDCharacter)
    }

    static func isValidListID<S: StringProtocol>(_ value: S) -> Bool {
        (2...128).contains(value.count) && value.allSatisfy(isIDCharacter)
    }

    private static func isIDCharacter(_ character: Character) -> Bool {
        guard character.isASCII else { return false }
        return character.isLetter || character.isNumber || character == "-" || character == "_"
    }

    static func normalizedHost(_ host: String) -> String {
        let lower = host.lowercased()
        for prefix in ["www.", "m.", "music.", "gaming."] where lower.hasPrefix(prefix) {
            return String(lower.dropFirst(prefix.count))
        }
        return lower
    }

    private static func parseURLString(_ raw: String) -> YouTubeLink? {
        var text = raw.trimmingCharacters(in: CharacterSet(charactersIn: "<>()[]\"'.,;"))
        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            guard lower.contains("youtu") else { return nil }
            text = "https://" + text
        }
        guard let components = URLComponents(string: text),
              let rawHost = components.host, !rawHost.isEmpty else { return nil }

        let host = normalizedHost(rawHost)
        let items = components.queryItems ?? []
        func query(_ name: String) -> String? {
            items.first(where: { $0.name == name })?.value
        }
        let start = parseTime(query("t") ?? query("start") ?? fragmentTime(components.fragment))
        let parts = components.path.split(separator: "/").map(String.init)

        switch host {
        case "youtu.be":
            guard let id = parts.first, isValidVideoID(id) else { return nil }
            return .video(id: id, start: start)

        case "youtube.com", "youtube-nocookie.com":
            if parts.first == "watch" {
                if let v = query("v"), isValidVideoID(v) {
                    return .video(id: v, start: start)
                }
                if let list = query("list"), isValidListID(list) {
                    return .playlist(id: list)
                }
                return nil
            }
            if parts.count >= 2,
               ["shorts", "embed", "live", "v", "e"].contains(parts[0].lowercased()),
               isValidVideoID(parts[1]) {
                return .video(id: parts[1], start: start)
            }
            if parts.first == "playlist" {
                guard let list = query("list"), isValidListID(list) else { return nil }
                return .playlist(id: list)
            }
            // Sonstige YouTube-Seiten (Kanal, Suche, Feed …) in der normalen Ansicht öffnen.
            guard host == "youtube.com" else { return nil }
            var page = URLComponents()
            page.scheme = "https"
            page.host = siteHost
            page.path = components.path.isEmpty ? "/" : components.path
            page.queryItems = components.queryItems
            return page.url.map { .page($0) }

        default:
            return nil
        }
    }

    private static func fragmentTime(_ fragment: String?) -> String? {
        guard let fragment, fragment.hasPrefix("t=") else { return nil }
        return String(fragment.dropFirst(2))
    }

    /// Akzeptiert "90", "90s", "1m30s", "1h2m3s".
    static func parseTime(_ value: String?) -> Int? {
        guard let raw = value?.lowercased(), !raw.isEmpty else { return nil }
        if let seconds = Int(raw) { return seconds >= 0 ? seconds : nil }
        var total = 0
        var number = ""
        var matchedUnit = false
        for character in raw {
            if character.isASCII, character.isNumber {
                number.append(character)
                continue
            }
            guard let value = Int(number) else { return nil }
            switch character {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: return nil
            }
            number = ""
            matchedUnit = true
        }
        guard number.isEmpty, matchedUnit else { return nil }
        return total
    }
}
