//
//  Demonic_VRApp.swift
//  Demonic VR
//
//  Created by David Martens on 22.11.26.
//

import SwiftUI

@main
struct Demonic_VRApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(DemonicTheme.accent)
        }
    }
}

enum DemonicTheme {
    static let accent = Color(red: 0.55, green: 1.0, blue: 0.2)
    static let violet = Color(red: 0.62, green: 0.27, blue: 0.95)
    static let background = Color(red: 0.05, green: 0.02, blue: 0.09)
    static let panel = Color(red: 0.11, green: 0.06, blue: 0.17)
}
