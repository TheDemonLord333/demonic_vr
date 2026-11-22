//
//  MirrorCinemaView.swift
//  Demonic VR
//
//  Experimenteller Cardboard-Weg ohne Bildkopie: Die echte, einzige WKWebView
//  (die „Original-Instanz“) wird in eine Augenhälfte gelegt und so skaliert und
//  beschnitten, dass nur das erkannte Videorechteck die Leinwand füllt. Ein
//  CAReplicatorLayer (öffentliche Core-Animation-API) zeichnet eine zweite
//  Instanz desselben Ebenenbaums, verschoben in die andere Augenhälfte
//  („Replikat“). Es werden keine Pixel ausgelesen und keine Stream-URLs
//  verwendet. Ton und Player bleiben in der WebView.
//
//  Zuordnung (Standard `.originalLeft`): Instanz 0 = Original = LINKE Hälfte,
//  Instanz 1 = Replikat = RECHTE Hälfte. Links/rechts sind die Bildschirmhälften
//  im Querformat aus Sicht des Betrachters (UIKit-Koordinaten x < Mitte = links).
//
//  Gerätebeobachtung (YouTube, iPhone 17 Pro): Videobild nur rechts, links schwarz,
//  HTML-Bedienelemente auf beiden Seiten. Rechts liegt im Standardmodus das
//  REPLIKAT. Das Videobild erscheint also nur in der replizierten Instanz, die
//  HTML-Oberfläche in beiden. Ob das an der Videoebene von WebKit liegt (eigene,
//  vom Render-Server eingebettete Ebene), an der Quelle oder an Inhaltsschutz,
//  ist NICHT geklärt. Zur Eingrenzung gibt es den lokalen Vergleichstest und die
//  Anordnungen `.originalRight` und `.originalOnly` (siehe MirrorDisplayMode).
//

import QuartzCore
import SwiftUI
import UIKit
import WebKit

/// Anordnung von Original-Instanz und Replikat – für den Vergleichstest umschaltbar.
nonisolated enum MirrorDisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Original links, Replikat rechts (Standard).
    case originalLeft
    /// Original rechts, Replikat links – trennt „Hälfte“ von „Instanz“.
    case originalRight
    /// Nur das Original links, kein Replikat – zeigt, ob das Original allein Video zeigt.
    case originalOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .originalLeft: return "Original links · Replikat rechts"
        case .originalRight: return "Original rechts · Replikat links"
        case .originalOnly: return "Nur Original links · ohne Replikat"
        }
    }

    var originalIsLeft: Bool { self != .originalRight }
    var replicates: Bool { self != .originalOnly }

    /// Beschriftung der Bildschirmhälfte.
    func role(leftHalf: Bool) -> String {
        if leftHalf {
            return originalIsLeft ? "Original-WebView" : "Replikat (CAReplicatorLayer)"
        }
        switch self {
        case .originalLeft: return "Replikat (CAReplicatorLayer)"
        case .originalRight: return "Original-WebView"
        case .originalOnly: return "leer (kein Replikat)"
        }
    }
}

/// Tatsächliche Geometrie einer Spiegel-Darstellung (für Bericht und Tests).
nonisolated struct MirrorGeometry: Equatable, Sendable {
    var containerSize: CGSize
    var pageSize: CGSize
    var videoRect: CGRect?
    var sourceRect: CGRect
    /// Sichtbarer Bereich der Original-Instanz im Container.
    var originalRect: CGRect
    /// Sichtbarer Bereich des Replikats im Container (leer ohne Replikat).
    var replicaRect: CGRect
    var instanceCount: Int
}

struct MirrorCinemaView: UIViewRepresentable {
    let player: PlayerController
    let settings: CalibrationSettings
    let mode: MirrorDisplayMode
    /// Aktueller Seitenstatus. Ändert er sich, wird die Leinwand neu ausgerichtet.
    let status: PlaybackStatus
    var onGeometry: (MirrorGeometry) -> Void = { _ in }

    func makeUIView(context: Context) -> MirrorCinemaContainer {
        let view = MirrorCinemaContainer()
        view.player = player
        return view
    }

    func updateUIView(_ view: MirrorCinemaContainer, context: Context) {
        view.player = player
        view.settings = settings
        view.mode = mode
        view.onGeometry = onGeometry
        view.videoRect = status.hasVideo ? status.contentRect : nil
        view.adoptWebViewIfPossible()
        view.setNeedsLayout()
    }

    static func dismantleUIView(_ view: MirrorCinemaContainer, coordinator: ()) {
        view.releaseWebView()
    }
}

final class MirrorCinemaContainer: UIView {
    override class var layerClass: AnyClass { CAReplicatorLayer.self }

    weak var player: PlayerController?
    var settings = CalibrationSettings.default
    var mode: MirrorDisplayMode = .originalLeft
    var videoRect: CGRect?
    var onGeometry: (MirrorGeometry) -> Void = { _ in }
    private(set) var lastGeometry: MirrorGeometry?

    /// Augenfenster (beschneidet auf die Leinwand). Wird mitsamt Inhalt repliziert.
    private let eyeClip = UIView()
    /// Bühne, die die WebView trägt und skaliert.
    private let stage = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = .black
        eyeClip.clipsToBounds = true
        eyeClip.backgroundColor = .black
        addSubview(eyeClip)
        eyeClip.addSubview(stage)
        if let replicator = layer as? CAReplicatorLayer {
            replicator.instanceCount = 2
            replicator.preservesDepth = false
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        adoptWebViewIfPossible()
    }

    /// Übernimmt dieselbe WebView-Instanz – nur solange der Spiegel-Modus aktiv ist.
    /// Nach `exitCardboard` (mirrorSessionActive = false) wird sie nicht erneut übernommen,
    /// auch wenn SwiftUI diese Ansicht während der Ausblendung noch aktualisiert.
    func adoptWebViewIfPossible() {
        guard window != nil, let player, player.mirrorSessionActive, let webView = player.webView else { return }
        guard webView.superview !== stage else { return }
        // Größe beibehalten, damit die Seite nicht neu umbricht und die Videoposition stimmt.
        let size = webView.bounds.size
        player.lendWebView()
        webView.removeFromSuperview()
        webView.autoresizingMask = []
        webView.frame = CGRect(origin: .zero, size: size)
        stage.transform = .identity
        stage.bounds = CGRect(origin: .zero, size: size)
        stage.addSubview(webView)
        setNeedsLayout()
    }

    func releaseWebView() {
        player?.returnWebViewHome()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let webView = player?.webView, webView.superview === stage else { return }
        let geometry = applyLayout(pageSize: webView.bounds.size)
        if let geometry, geometry != lastGeometry {
            lastGeometry = geometry
            let callback = onGeometry
            // Nicht während eines Layout-/View-Updates beobachtbaren Zustand ändern.
            Task { @MainActor in callback(geometry) }
        }
    }

    /// Setzt Augenfenster, Bühne und Replikator für eine Seite der Größe `pageSize`.
    ///
    /// Beide Instanzen des CAReplicatorLayer zeigen denselben Inhalt, nur um `dx` verschoben.
    /// Eine unterschiedliche Beschneidung pro Auge (wie in `StereoCinemaView`) ist damit nicht
    /// möglich. Deshalb wird die Quelle auf den Bereich begrenzt, der in der Hälfte des
    /// Originals liegt und nach der Verschiebung in der Hälfte des Replikats.
    @discardableResult
    func applyLayout(pageSize: CGSize) -> MirrorGeometry? {
        guard bounds.width > 0, bounds.height > 0, pageSize.width > 0, pageSize.height > 0 else { return nil }

        stage.bounds = CGRect(origin: .zero, size: pageSize)
        let source = Self.sourceRect(video: videoRect, page: pageSize, crop: settings.effectiveCrop)
        let layout = StereoLayout.compute(container: bounds.size,
                                          contentAspect: source.width / max(source.height, 1),
                                          settings: settings)
        let originalScreen = mode.originalIsLeft ? layout.leftScreen : layout.rightScreen
        let dx = Self.replicaOffset(for: layout, mode: mode)
        let visible = Self.visibleScreenRect(for: layout, mode: mode)

        eyeClip.isHidden = visible.isEmpty
        eyeClip.frame = visible.isEmpty ? .zero : visible

        // Quelle auf die volle Leinwand des Originals abbilden; das Augenfenster schneidet nur zu.
        let scale = originalScreen.width / max(source.width, 1)
        let screenOrigin = CGPoint(x: originalScreen.minX - eyeClip.frame.minX,
                                   y: originalScreen.minY - eyeClip.frame.minY)
        stage.transform = CGAffineTransform(scaleX: scale, y: scale)
        stage.center = CGPoint(x: screenOrigin.x + scale * (pageSize.width / 2 - source.minX),
                               y: screenOrigin.y + scale * (pageSize.height / 2 - source.minY))

        let instances = mode.replicates ? 2 : 1
        if let replicator = layer as? CAReplicatorLayer {
            replicator.instanceCount = instances
            replicator.instanceTransform = CATransform3DMakeTranslation(dx, 0, 0)
        }
        return MirrorGeometry(containerSize: bounds.size,
                              pageSize: pageSize,
                              videoRect: videoRect,
                              sourceRect: source,
                              originalRect: eyeClip.frame,
                              replicaRect: mode.replicates ? eyeClip.frame.offsetBy(dx: dx, dy: 0) : .zero,
                              instanceCount: instances)
    }

    /// Verschiebung des Replikats gegenüber dem Original.
    nonisolated static func replicaOffset(for layout: StereoLayout, mode: MirrorDisplayMode = .originalLeft) -> CGFloat {
        guard mode.replicates else { return 0 }
        return mode.originalIsLeft
            ? layout.rightScreen.minX - layout.leftScreen.minX
            : layout.leftScreen.minX - layout.rightScreen.minX
    }

    /// Teil der Leinwand des Originals, der in dessen Augenhälfte liegt und dessen verschobene
    /// Kopie vollständig in der anderen Augenhälfte liegt.
    nonisolated static func visibleScreenRect(for layout: StereoLayout, mode: MirrorDisplayMode = .originalLeft) -> CGRect {
        let originalScreen = mode.originalIsLeft ? layout.leftScreen : layout.rightScreen
        let originalEye = mode.originalIsLeft ? layout.leftEye : layout.rightEye
        let replicaEye = mode.originalIsLeft ? layout.rightEye : layout.leftEye
        var rect = originalScreen.intersection(originalEye)
        if mode.replicates {
            let dx = replicaOffset(for: layout, mode: mode)
            rect = rect.intersection(replicaEye.offsetBy(dx: -dx, dy: 0))
        }
        return rect.isNull ? .zero : rect
    }

    // Für Tests: tatsächliche Geometrie der Ansichten und Ebenen.
    var eyeClipView: UIView { eyeClip }
    var stageView: UIView { stage }

    /// Bereich der Seite, der die Leinwand füllt: Videobild, darin der manuelle Ausschnitt.
    nonisolated static func sourceRect(video: CGRect?, page: CGSize, crop: NormalizedRect) -> CGRect {
        let pageRect = CGRect(origin: .zero, size: page)
        var base = video?.intersection(pageRect) ?? pageRect
        if base.isNull || base.width < 16 || base.height < 16 { base = pageRect }
        let c = crop.clamped()
        return CGRect(x: base.minX + c.x * base.width,
                      y: base.minY + c.y * base.height,
                      width: c.width * base.width,
                      height: c.height * base.height)
    }
}
