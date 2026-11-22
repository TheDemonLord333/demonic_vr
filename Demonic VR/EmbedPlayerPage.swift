//
//  EmbedPlayerPage.swift
//  Demonic VR
//
//  Lokale Seite mit dem offiziellen YouTube IFrame Player. Nutzt nur
//  dokumentierte Player-Parameter und -Ereignisse; die YouTube-Bedienelemente
//  und das Branding bleiben sichtbar (controls nicht deaktiviert).
//

import Foundation

nonisolated enum EmbedPlayerPage {
    static func html(videoID: String, start: Int, origin: URL) -> String {
        // Video-ID ist auf [A-Za-z0-9_-]{11} geprüft; trotzdem als JSON-String einsetzen.
        let idLiteral = jsonString(videoID)
        let originLiteral = jsonString(origin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        let startValue = max(start, 0)
        return """
        <!doctype html>
        <html lang="de">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>
          html, body { margin: 0; height: 100%; background: #000; }
          #wrap { display: flex; align-items: center; justify-content: center; width: 100%; height: 100%; }
          #player { width: 100%; aspect-ratio: 16 / 9; max-height: 100%; }
        </style>
        </head>
        <body>
        <div id="wrap"><div id="player"></div></div>
        <script>
          window.__demonicEmbed = true;
          function post(m) {
            try { window.webkit.messageHandlers.\(PlayerController.messageHandlerName).postMessage(m); } catch (e) {}
          }
          var tag = document.createElement('script');
          tag.src = 'https://www.youtube.com/iframe_api';
          tag.onerror = function () { post({ type: 'error', code: -2 }); };
          document.head.appendChild(tag);
          function onYouTubeIframeAPIReady() {
            window.__demonicPlayer = new YT.Player('player', {
              videoId: \(idLiteral),
              playerVars: { playsinline: 1, start: \(startValue), rel: 0, origin: \(originLiteral) },
              events: {
                onReady: function () { post({ type: 'ready' }); },
                onStateChange: function (e) { post({ type: 'state', state: e.data }); },
                onError: function (e) { post({ type: 'error', code: e.data }); }
              }
            });
          }
        </script>
        </body>
        </html>
        """
    }

    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8) else { return "\"\"" }
        // "[\"…\"]" → "\"…\""
        return String(array.dropFirst().dropLast())
    }
}
