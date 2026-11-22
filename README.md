# Demonic VR

**Demonic VR** spielt YouTube auf dem iPhone ab und zeigt das Bild für eine
Cardboard-Brille als flache Kinoleinwand im Querformat – mit demselben Bild für
beide Augen.

- Bundle-ID: `me.thedemonlord333.Demonic-VR`, automatisches Signing
- Deployment Target: iOS 26.2, Swift / SwiftUI
- Zielgerät: iPhone 17 Pro

## Start

1. `Demonic VR.xcodeproj` in der Repo-Wurzel mit Xcode öffnen.
2. Scheme **Demonic VR** wählen (prüfen mit
   `xcodebuild -list -project "Demonic VR.xcodeproj"`).
3. Unter *Signing & Capabilities* das eigene Team wählen, falls nötig.
4. iPhone 17 Pro (Gerät oder Simulator) wählen und starten.

Alle Quelltexte liegen in `Demonic VR/`. Der Ordner ist eine Xcode-Gruppe, die
mit dem Dateisystem synchronisiert wird. Jede `.swift`-Datei darin wird
automatisch vom App-Target kompiliert, ein Eintrag in der `project.pbxproj` ist
dafür nicht nötig.

| Datei | Inhalt |
| --- | --- |
| `Demonic_VRApp.swift` | `@main`-Einstieg, App-Delegate (Querformat-Sperre, Audio-Session) |
| `ContentView.swift` | Startansicht: WebView, Link-Eingabe, Navigation, Fehler-Banner |
| `PlayerController.swift` | Die **eine** persistente `WKWebView`, Navigation, Status-Skript, Fehlerbehandlung |
| `EmbedPlayerPage.swift` | Optionaler offizieller YouTube-IFrame-Player |
| `YouTubeLink.swift` | Erkennung von YouTube-Links |
| `SnapshotEngine.swift` | WebKit-Snapshots (`takeSnapshot(with:)`), höchstens ein Aufruf gleichzeitig |
| `FrameAnalysis.swift` | Erkennung neuer, wiederholter und schwarzer Frames, Statistik, Freigabe-Logik |
| `ReferenceScene.swift` | Animierte lokale Referenzszene mit Framezähler |
| `CardboardView.swift` | Stereo-Leinwand (beide Augen in einem Canvas-Durchgang aus demselben Frame) |
| `StereoLayout.swift` | Geometrie: Leinwandgröße, Abstand, vertikale Position, Ausschnitt |
| `Calibration.swift`, `CalibrationView.swift` | Kalibrierung, gespeichert in `UserDefaults` |
| `DiagnosticsView.swift` | Einzelbild- und Live-Test, Cardboard-Freigabe |
| `GoogleAccount.swift`, `PlaylistsView.swift` | Optionale Playlist-Ansicht (Google-OAuth + YouTube Data API) |

Der sichtbare Name ist auf dem Home-Bildschirm und in der App „Demonic VR“
(`INFOPLIST_KEY_CFBundleDisplayName`).

## App-Icon

- Quelle: `Obsidian horned VR headset.png` in der Repo-Wurzel (bleibt dort).
  Die Datei hat 1254 × 1254 px, RGB und keinen Alphakanal.
- Aufbereitet als `Demonic VR/Assets.xcassets/AppIcon.appiconset/AppIcon.png`:
  1024 × 1024 px, RGB ohne Alphakanal, auf das ganze Bild skaliert (Lanczos).
  Das vollständige Motiv und die eckige Bildfläche bleiben erhalten, die
  Rundung macht iOS.
- In `AppIcon.appiconset/Contents.json` beim universellen iOS-Standardeintrag
  (`1024x1024`, ohne Appearance) eingetragen. Das App-Target verweist über
  `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` auf das Set. Für die Varianten
  „dark“ und „tinted“ ist bewusst nichts hinterlegt, iOS leitet sie ab.

Neu erzeugen (zum Beispiel mit Python/Pillow):

```sh
python3 -c "from PIL import Image; Image.open('Obsidian horned VR headset.png').convert('RGB').resize((1024,1024), Image.LANCZOS).save('Demonic VR/Assets.xcassets/AppIcon.appiconset/AppIcon.png')"
```

## Funktionen

### YouTube-Wiedergabe

- Es gibt genau **eine** `WKWebView`. Der `PlayerController` erzeugt sie
  einmal, und zwar erst, wenn ihr Container im App-Fenster hängt. Danach hängt
  sie dauerhaft in der Startansicht. (Unter iOS 26 stürzt eine WebView, die vor
  dem Fenster erzeugt wurde, beim ersten Tipp in
  `-[UIGestureRecognizer _delayTouchesForEvent:inPhase:]` ab.) Cardboard, Diagnose und
  Kalibrierung legen sich als Ebene oder Sheet darüber. So bleiben Sitzung,
  Cookies, Wiedergabe, Position und der einzige Audiopfad bei jedem Wechsel
  erhalten.
- Die normale mobile YouTube-Ansicht (`m.youtube.com`) startet automatisch.
  Für die Grundfunktionen ist keine Google-Anmeldung nötig.
- Inline-Wiedergabe: `allowsInlineMediaPlayback = true`, kein Benutzer-Tap für
  Medien nötig. Bild-in-Bild und AirPlay sind aus, damit es bei einem Player
  bleibt.
- **Link einfügen:** Über das Textfeld oder den Einfügen-Button. Erkannt werden
  `watch?v=`, `youtu.be/`, `/shorts/`, `/live/`, `/embed/`, Startzeiten (`t=`)
  und Playlists. Links öffnen standardmäßig in der normalen YouTube-Ansicht.
  Optional (Menü „…“) öffnen sie im offiziellen IFrame-Player.
- **Klarer Rückweg:** Bei ungültigen Links, Ladefehlern, beendetem Web-Prozess
  oder IFrame-Fehlern (2, 5, 100, 101/150, 152/153) erscheint ein Banner. Es
  bietet „In YouTube-Ansicht öffnen“, „Zur YouTube-Startseite“, „Erneut
  versuchen“ oder „Schließen“.
- Die Statuszeile zeigt Quelle, Position und WebView-Kennung. Nach dem
  Verlassen von Cardboard steht dort auch der Sitzungsvergleich vorher/nachher:
  gleiche WebView, gleiche Seite, Position nicht zurückgesetzt.

### IFrame-API (optional)

Der IFrame-Player nutzt nur dokumentierte Parameter und Ereignisse:
`playsinline`, `start`, `rel`, `origin`, `onReady`, `onStateChange`,
`onError`, `getCurrentTime`, `getDuration` und `getPlayerState`. Die
YouTube-Bedienelemente und das Branding bleiben sichtbar, `controls` wird nicht
abgeschaltet. Als Origin und Referrer dient `https://me.thedemonlord333.demonic-vr`,
also die Bundle-ID, wie es YouTube für App-WebViews verlangt. Weil der
IFrame-Player laut YouTube-API-Richtlinien nicht verdeckt werden darf, ist
**Cardboard für den IFrame-Player gesperrt**. Für Cardboard das Video in der
normalen YouTube-Ansicht öffnen.

### Cardboard-Modus

- Querformat wird erzwungen, Statusleiste und Home-Indikator sind ausgeblendet,
  der Bildschirm bleibt an.
- Beide Augenhälften zeigen denselben zugeschnittenen Frame aus derselben
  Quelle, mit korrektem Seitenverhältnis und symmetrisch zur Mitte. Beide Augen
  werden in **einem** `Canvas`-Durchgang aus demselben `VideoFrame`-Objekt
  gezeichnet. Bei Pufferung oder Aussetzern bleibt in beiden Augen derselbe
  letzte Frame stehen. Unter jeder Leinwand steht dieselbe Framenummer.
- **Kalibrierung** (in der Brille über „Kalibrierung“ oder von der
  Startansicht aus): Leinwandgröße, horizontaler Abstand, vertikale Position und
  ein manueller Ausschnitt (links/oben/Breite/Höhe). Die Werte werden sofort in
  `UserDefaults` gespeichert (`demonicvr.calibration.v1`). „Auf Standard
  zurücksetzen“ löscht sie.
- **Referenzszene:** Eine animierte lokale 16:9-Szene mit Framezähler, Raster,
  Eckmarken, bewegter Kugel und einer 60-Felder-Frameleiste. Damit lassen sich
  Ausschnitt und Synchronität ohne YouTube prüfen. Mit „Aussetzer“ werden
  Pufferpausen simuliert.

### Snapshot-Diagnose

Erreichbar über „Diagnose“, auch aus Cardboard und aus dem Problem-Hinweis.

- **Einzelbildtest** und **Live-Test (10 s)** für die YouTube-WebView über die
  öffentliche API `WKWebView.takeSnapshot(with:completionHandler:)`. Gleiche
  Tests gibt es für die Referenzszene.
- Angezeigt werden: Vorschau (mit Ausschnittsrahmen und Stereo-Vorschau),
  Snapshot-Dauer (letzte, Durchschnitt, Maximum), gelieferte und tatsächlich
  neue Frames pro Sekunde (gesamt und gleitend), wiederholte und schwarze
  Frames, Fehler, die Höchstzahl gleichzeitig offener Snapshots und der
  erfasste Bereich.
- Erfasst wird nur der sichtbare Video-Bildbereich: Element-Rechteck ohne
  Letterbox, ermittelt über `getBoundingClientRect` und `videoWidth`/`videoHeight`.
  „Bewegung im Ausschnitt erkannt“ zeigt an, ob sich der Bereich wirklich ändert.
- Es ist höchstens ein Snapshot-Aufruf gleichzeitig offen: Die Aufrufe laufen
  nacheinander, zusätzlich verhindert ein Zähler Überschneidungen. Die Rate ist
  auf höchstens 30/s begrenzt.
- Die Aufnahme endet beim Schließen der Diagnose, beim Verlassen von Cardboard,
  bei `willResignActive`/`didEnterBackground` und bei Szenenwechseln.

### YouTube in Cardboard ist experimentell

Cardboard für YouTube wird erst freigegeben, wenn

1. die Quelle die normale YouTube-Ansicht ist (nicht der IFrame-Player und
   keine fremde Seite),
2. die Hinweise bestätigt sind: Wiedergabe, Werbung, Bedienelemente und Ton
   bleiben im YouTube-Player, Cardboard zeigt nur Snapshots für die private
   Betrachtung, und
3. ein Live-Test laufend nutzbare Frames liefert: mindestens 8 neue Frames/s,
   höchstens 50 % schwarze Frames, kein Stillstand über 1,5 s und Messdauer
   mindestens 2 s.

Während Cardboard läuft, wird das Bild weiter überwacht. Wird es schwarz oder
friert es ein, erscheint ein Hinweis mit „Diagnose“ und „Zurück zum Player“.
„Zurück zum Player“ ist in der Bedienleiste immer erreichbar (Tippen blendet sie
ein).

Es werden **keine privaten APIs** verwendet, **keine Stream-URLs** gelesen und
**kein Kopierschutz** umgangen. Das injizierte Skript liest nur Position, Größe
und Abspielzeit des sichtbaren `<video>`-Elements. Liefert WebKit für das Video
nur schwarze oder eingefrorene Bilder, etwa weil die Videoebene hardwareseitig
oder geschützt gerendert wird, bleibt Cardboard für YouTube gesperrt.

### Spiegel-Modus für YouTube (experimenteller Versuch)

Der Snapshot-Weg liefert für YouTube kein nutzbares Bild (Messwerte siehe
„Stand der Prüfung“) und bleibt gesperrt. Der Spiegel-Modus ist ein
**experimenteller Versuch** ohne Bildkopie. Ob er auf dem iPhone funktioniert,
ist **noch nicht geprüft**.

- Dieselbe WebView-Instanz wird für die Dauer von Cardboard ins linke Auge
  gelegt. Sie wird so skaliert und beschnitten, dass das Videobild (mit
  optionalem Ausschnitt) die Leinwand füllt.
- Ein `CAReplicatorLayer` (öffentliche Core-Animation-API) dupliziert diese
  Ebene beim Compositing ins rechte Auge. **Ob iOS die Videoebene der
  WKWebView mitrepliziert, ist offen.** Nur wenn das der Fall ist, zeigen beide
  Augen denselben Frame.
- Jede Kopie bleibt in ihrer Augenhälfte. Beide Instanzen des Replikators
  zeigen zwangsläufig denselben Inhalt, nur verschoben. Deshalb wird die
  Leinwand auf den Teil begrenzt, der links in der linken und, verschoben, rechts
  in der rechten Augenhälfte liegt. Bei stark negativem Abstand oder sehr großer
  Leinwand werden dadurch in **beiden** Augen dieselben Ränder abgeschnitten.
  Die Snapshot-/Referenzansicht (`StereoCinemaView`) schneidet dagegen pro Auge
  nur den Rand an der Bildschirmmitte ab.
- Ton, Werbung und Bedienelemente bleiben im YouTube-Player. Es werden keine
  Pixel gelesen und keine Stream-URLs verwendet.
- Start nur mit bestätigten Hinweisen und laufendem Video in der
  YouTube-Ansicht.
- Nach dem Start ist eine **Sichtprüfung beider Augen** nötig: „Ja, beide
  Augen“, „Diagnose“ oder „Nein – zum Player“.
- Beim Verlassen kehrt die WebView ohne Neuladen an ihren Platz zurück. Die
  Statuszeile zeigt dann den Sitzungsvergleich.

### Optionale Playlist-Ansicht

Die Playlist-Ansicht nutzt den offiziellen Google-OAuth-2.0-Ablauf für native
Apps (Autorisierungscode mit PKCE) über `ASWebAuthenticationSession`, ganz
getrennt von der WebView-Sitzung. Dazu kommt die YouTube Data API v3
(`playlists?mine=true`, `playlistItems`). Tokens liegen nur im Arbeitsspeicher.

Einrichtung:

1. In der Google Cloud Console die **YouTube Data API v3** aktivieren.
2. Einen OAuth-Zustimmungsbildschirm anlegen (Scope `youtube.readonly`).
3. Eine **OAuth-Client-ID vom Typ „iOS“** für die Bundle-ID
   `me.thedemonlord333.Demonic-VR` anlegen.
4. `Config/GoogleOAuth.example.plist` nach `Demonic VR/GoogleOAuth.plist`
   kopieren und `CLIENT_ID` eintragen. Die Datei steht in `.gitignore` und
   **darf nicht committet werden**. Als Redirect dient die umgekehrte
   Client-ID (`com.googleusercontent.apps.…:/oauth2redirect`).

Ohne diese Datei zeigt die Playlist-Ansicht nur die Anleitung, der Rest der App
funktioniert normal.

## Tests

### Automatisch (Xcode, Simulator oder Gerät)

```sh
xcodebuild -list -project "Demonic VR.xcodeproj"
xcodebuild test -project "Demonic VR.xcodeproj" -scheme "Demonic VR" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro"
```

- `Demonic VRTests`: Link-Erkennung, Rückweg bei ungültigen Links und
  IFrame-Fehlern, eine WebView über Ansichtswechsel, Stereo-Layout
  (Symmetrie, Seitenverhältnis, Abstand, vertikale Position), Letterbox,
  Ausschnitt, Speichern/Laden/Zurücksetzen der Kalibrierung, Erkennung neuer,
  wiederholter und schwarzer Frames, Statistik, Freigabe-Logik, Quellenregeln,
  Referenzszene, PKCE und OAuth-Redirect sowie die Begrenzung des
  Spiegel-Modus: echte Ebene und replizierte Kopie bleiben bei allen
  Grenzwerten in ihrer Augenhälfte (`MirrorClippingRegressionTests`).
- `Demonic VRUITests`: Start mit dem Namen „Demonic VR“, Referenzszene im
  Querformat mit laufendem Framezähler und Rückkehr zum Player, Kalibrierung
  und Zurücksetzen, ungültiger Link mit Rückweg, Live-Test der Referenzszene
  mit erkannter Bewegung, gesperrte YouTube-Freigabe ohne Quelle,
  Launch-Performance. UI-Tests starten mit `-DemonicUITest`, ohne Netzwerk und
  mit eigener `UserDefaults`-Suite.

### Manuell auf dem iPhone 17 Pro

1. **Name und Icon:** Auf dem Home-Bildschirm stehen „Demonic VR“ und das
   Headset-Icon.
2. **Referenzszene:** „Referenz“ antippen. Die App dreht ins Querformat, beide
   Augen zeigen dieselbe Framenummer und dasselbe Feld der Frameleiste. Mit
   „Aussetzer“ bleibt in beiden Augen derselbe Frame stehen. In der Brille
   Leinwandgröße, Abstand und vertikale Position einstellen, die App neu
   starten und prüfen, ob die Werte erhalten bleiben. Dann zurücksetzen.
3. **YouTube:** Ein Video in der YouTube-Ansicht starten und einen Link
   einfügen, zum Beispiel `https://youtu.be/<ID>`. Die Wiedergabe läuft inline.
4. **Diagnose:** „Diagnose“ → Quelle „YouTube-WebView“ → Einzelbildtest, dann
   Live-Test. Die Vorschau muss das Videobild zeigen (nicht schwarz), „neu“ muss
   deutlich über 0 fps liegen und „Bewegung im Ausschnitt erkannt“ erscheinen.
   Gleichzeitig offene Snapshots müssen 1 bleiben.
5. **Cardboard-Freigabe:** „Cardboard β“ → Hinweise bestätigen → Prüfung
   abwarten → „Cardboard starten“. Ton und Bild müssen weiterlaufen.
6. **Rückkehr:** „Zurück zum Player“. Die Statuszeile meldet „WebView gleich ·
   Seite gleich · Position x → y“ mit y ≥ x, und das Video läuft ohne Neuladen
   weiter. Ein ungültiger Link zeigt das Banner mit Rückweg.
7. **Hintergrund:** In Cardboard oder während eines Live-Tests die App in den
   Hintergrund schicken. Die Aufnahme stoppt, im Diagnose-Status steht „Bereit“.
8. **Schwarzes oder eingefrorenes Bild:** Liefert YouTube in Cardboard keine
   Frames, erscheint der Hinweis mit „Diagnose“ und „Zurück zum Player“, und
   beides funktioniert.

### iPhone-Testfolge Spiegel-Modus (neuer Stand, noch offen)

1. **Beide Augen:** YouTube-Video in der YouTube-Ansicht starten → „Cardboard β“
   → Hinweise bestätigen → „Spiegel-Cardboard starten“. In der Brille prüfen:
   Läuft das Video im linken **und** rechten Auge, gleich und flüssig? Ist ein
   Auge schwarz oder eingefroren, „Nein – zum Player“ wählen und das Ergebnis
   notieren.
2. **Kalibrierung:** Über „Kalibrierung“ Leinwandgröße 40 % und 100 %,
   horizontalen Abstand −25 %, 0 % und +25 % sowie vertikale Position −50 % und
   +50 % einstellen, zusätzlich einen manuellen Ausschnitt. Jede Leinwand muss
   in ihrer Augenhälfte bleiben, ohne über die Mitte zu ragen, und beide Augen
   müssen dasselbe Bild zeigen.
3. **Rückkehr:** „Zurück zum Player“. Das Video läuft an derselben Position
   weiter, ohne Neuladen und mit Ton. Die Statuszeile meldet „WebView gleich ·
   Seite gleich“, und die Seite lässt sich wieder normal bedienen.
4. **Erneut öffnen:** Den Spiegel-Modus noch einmal starten und Schritt 1 kurz
   wiederholen.

## Stand der Prüfung

**Auf dem iPhone geprüft (Nutzertest, Stand vor dem Spiegel-Modus):**

- Die App startet, die Startansicht ist bedienbar, und seit der verzögerten
  WebView-Erzeugung lässt sich auch die YouTube-Seite bedienen.
- YouTube läuft im normalen WebView-Player sichtbar.
- YouTube-Snapshots: In 10 s kamen 286 bzw. 288 Bilder, davon jeweils nur
  **ein** als neu erkanntes Bild. Die gemessene durchschnittliche Helligkeit
  betrug 7/255, der Zähler meldete **null** schwarze Frames, die Vorschau wirkte
  für den Nutzer aber schwarz. (Die Schwarz-Erkennung verlangt zusätzlich eine
  maximale Helligkeit unter 48. Einzelne hellere Pixel reichen also, damit ein
  dunkles Bild nicht als schwarz zählt.) Die Freigabe für Snapshot-Cardboard
  blieb wegen fehlender neuer Frames gesperrt.
- Referenzszene: 593 neue Bilder in 10 s. In der Cardboard-Referenzansicht lief
  sie flüssig und auf beiden Seiten synchron. Das gilt für den bisherigen
  Darstellungsweg mit lokal erzeugten Bildern (`StereoCinemaView`), **nicht**
  für den Spiegel-Modus.

**Noch nicht geprüft:**

- Der Spiegel-Modus auf dem Gerät (Testfolge oben), insbesondere ob iOS die
  Videoebene repliziert.
- Build, Unit- und UI-Tests in Xcode. Der Code entstand in einer
  Linux-Umgebung ohne macOS, Xcode und Swift-Compiler, deshalb liefen dort
  weder Build noch Tests.

Ohne Xcode geprüft wurden das App-Icon (1024 × 1024, RGB ohne Alpha),
sein Eintrag in `Contents.json`, der PKCE-Testvektor (RFC 7636) und die
Begrenzungsgeometrie des Spiegel-Modus (nachgerechnet, siehe Regressionstest).
