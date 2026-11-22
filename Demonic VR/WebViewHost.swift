//
//  WebViewHost.swift
//  Demonic VR
//
//  Bettet die eine, im PlayerController gehaltene WKWebView ein. Die
//  WebView wird hier weder erzeugt noch zerstört.
//

import SwiftUI
import UIKit
import WebKit

struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        attach(to: container)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if webView.superview !== container {
            attach(to: container)
        }
    }

    private func attach(to container: UIView) {
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
    }
}
