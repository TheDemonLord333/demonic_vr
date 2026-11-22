//
//  OrientationController.swift
//  Demonic VR
//
//  Erzwingt im Cardboard-Modus das Querformat und gibt danach alle
//  Ausrichtungen wieder frei.
//

import AVFoundation
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .allButUpsideDown

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Ein Audiopfad: der Ton der WebView, auch bei aktivem Stummschalter.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }
}

enum OrientationController {
    static func lockLandscape() {
        apply(mask: .landscape, request: .landscapeRight)
    }

    static func unlock() {
        apply(mask: .allButUpsideDown, request: .portrait)
    }

    private static func apply(mask: UIInterfaceOrientationMask, request: UIInterfaceOrientationMask) {
        AppDelegate.orientationLock = mask
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: request)) { _ in
                // Auf Geräten ohne Drehung (oder im Split-View auf dem iPad) ist das kein Fehler.
            }
        }
    }
}
