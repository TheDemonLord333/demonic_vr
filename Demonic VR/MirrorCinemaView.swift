//
//  MirrorCinemaView.swift
//  Demonic VR
//
//  Experimenteller Cardboard-Weg für YouTube ohne Bildkopie: Die echte, einzige
//  WKWebView wird ins linke Auge gelegt, so skaliert und beschnitten, dass nur
//  der Videobereich die Leinwand füllt. Ein CAReplicatorLayer (öffentliche
//  Core-Animation-API) dupliziert diese Ebene beim Compositing ins rechte Auge.
//  Falls iOS die Ebene repliziert, zeigen beide Augen denselben Frame. Jede
//  Kopie bleibt in ihrer Augenhälfte. Es werden keine Pixel ausgelesen
//  und keine Stream-URLs verwendet. Ton und Player bleiben in der WebView.
//
//  Ob iOS die Videoebene der WKWebView überhaupt mitrepliziert, ist offen und
//  auf dem iPhone noch nicht geprüft. Der Modus ist ein experimenteller Versuch;
//  die Cardboard-Ansicht verlangt deshalb eine Sichtprüfung beider Augen.
//

import QuartzCore
import SwiftUI
import UIKit
import WebKit

struct MirrorCinemaView: UIViewRepresentable {
    let player: PlayerController
    let settings: CalibrationSettings
    /// Aktueller Seitenstatus. Ändert er sich, wird die Leinwand neu ausgerichtet.
    let status: PlaybackStatus

    func makeUIView(context: Context) -> MirrorCinemaContainer {
        let view = MirrorCinemaContainer()
        view.player = player
        return view
    }

    func updateUIView(_ view: MirrorCinemaContainer, context: Context) {
        view.player = player
        view.settings = settings
        view.videoRect = status.hasVideo ? status.contentRect : nil
        view.adoptWebViewIfPossible()
        view.setNeedsLayout()
    }

    static func dismantleUIView(_ view: MirrorCinemaContainer, coordinator: ()) {
        view.player?.returnWebViewHome()
    }
}

final class MirrorCinemaContainer: UIView {
    override class var layerClass: AnyClass { CAReplicatorLayer.self }

    weak var player: PlayerController?
    var settings = CalibrationSettings.default
    var videoRect: CGRect?

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

    func adoptWebViewIfPossible() {
        guard window != nil, let player, let webView = player.webView else { return }
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

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let webView = player?.webView, webView.superview === stage else { return }
        applyLayout(pageSize: webView.bounds.size)
    }

    /// Setzt Augenfenster, Bühne und Replikator-Verschiebung für eine Seite der Größe `pageSize`.
    ///
    /// Beide Instanzen des CAReplicatorLayer zeigen denselben Inhalt, nur um `dx` verschoben.
    /// Eine unterschiedliche Beschneidung pro Auge (wie in `StereoCinemaView`) ist damit nicht
    /// möglich. Deshalb wird die Quelle auf den Bereich begrenzt, der links in `leftEye` und
    /// nach der Verschiebung rechts in `rightEye` liegt (`visibleScreenRect`). So bleibt jede
    /// Kopie in ihrer Augenhälfte, und beide Augen zeigen exakt dieselbe Leinwand.
    func applyLayout(pageSize: CGSize) {
        guard bounds.width > 0, bounds.height > 0, pageSize.width > 0, pageSize.height > 0 else { return }

        stage.bounds = CGRect(origin: .zero, size: pageSize)
        let source = Self.sourceRect(video: videoRect, page: pageSize, crop: settings.effectiveCrop)
        let layout = StereoLayout.compute(container: bounds.size,
                                          contentAspect: source.width / max(source.height, 1),
                                          settings: settings)
        let dx = Self.replicaOffset(for: layout)
        let visible = Self.visibleScreenRect(for: layout)

        eyeClip.isHidden = visible.isEmpty
        eyeClip.frame = visible.isEmpty ? .zero : visible

        // Quelle auf die volle linke Leinwand abbilden; das Augenfenster schneidet nur zu.
        let scale = layout.leftScreen.width / max(source.width, 1)
        let screenOrigin = CGPoint(x: layout.leftScreen.minX - eyeClip.frame.minX,
                                   y: layout.leftScreen.minY - eyeClip.frame.minY)
        stage.transform = CGAffineTransform(scaleX: scale, y: scale)
        stage.center = CGPoint(x: screenOrigin.x + scale * (pageSize.width / 2 - source.minX),
                               y: screenOrigin.y + scale * (pageSize.height / 2 - source.minY))

        if let replicator = layer as? CAReplicatorLayer {
            replicator.instanceTransform = CATransform3DMakeTranslation(dx, 0, 0)
        }
    }

    /// Verschiebung der replizierten Kopie (linke → rechte Leinwand).
    nonisolated static func replicaOffset(for layout: StereoLayout) -> CGFloat {
        layout.rightScreen.minX - layout.leftScreen.minX
    }

    /// Teil der linken Leinwand, der in `leftEye` liegt und dessen um `dx` verschobene Kopie
    /// vollständig in `rightEye` liegt.
    nonisolated static func visibleScreenRect(for layout: StereoLayout) -> CGRect {
        let dx = replicaOffset(for: layout)
        let rect = layout.leftScreen
            .intersection(layout.leftEye)
            .intersection(layout.rightEye.offsetBy(dx: -dx, dy: 0))
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
