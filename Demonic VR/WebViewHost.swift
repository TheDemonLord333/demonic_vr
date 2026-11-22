//
//  WebViewHost.swift
//  Demonic VR
//
//  Bettet die eine, im PlayerController gehaltene WKWebView ein. Sie wird
//  erst erzeugt, wenn der Container in einem Fenster hängt, und danach nie
//  zerstört oder neu angelegt.
//
//  Hintergrund: Unter iOS 26 stürzt eine WKWebView, die vor dem App-Fenster
//  erzeugt wurde, beim ersten Tipp in
//  -[UIGestureRecognizer _delayTouchesForEvent:inPhase:] ab.
//

import SwiftUI
import UIKit
import WebKit

struct WebViewHost: UIViewRepresentable {
    let player: PlayerController

    func makeUIView(context: Context) -> WebViewContainer {
        let container = WebViewContainer()
        container.player = player
        return container
    }

    func updateUIView(_ container: WebViewContainer, context: Context) {
        container.player = player
        container.attachIfPossible()
    }
}

final class WebViewContainer: UIView {
    weak var player: PlayerController?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachIfPossible()
    }

    func attachIfPossible() {
        guard window != nil, let player else { return }
        let webView = player.hostedWebView()
        guard webView.superview !== self else { return }
        webView.removeFromSuperview()
        webView.frame = bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(webView)
    }
}
