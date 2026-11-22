//
//  StereoLayout.swift
//  Demonic VR
//
//  Geometrie für die Cardboard-Darstellung: zwei gleich große Leinwände,
//  spiegelsymmetrisch zur Bildschirmmitte, mit korrektem Seitenverhältnis.
//

import CoreGraphics
import Foundation

nonisolated struct StereoLayout: Equatable, Sendable {
    var leftEye: CGRect
    var rightEye: CGRect
    var leftScreen: CGRect
    var rightScreen: CGRect

    static let fallbackAspect: CGFloat = 16.0 / 9.0

    static func compute(container: CGSize, contentAspect: CGFloat, settings: CalibrationSettings) -> StereoLayout {
        let s = settings.clamped()
        let width = max(container.width, 0)
        let height = max(container.height, 0)
        let half = width / 2
        let leftEye = CGRect(x: 0, y: 0, width: half, height: height)
        let rightEye = CGRect(x: half, y: 0, width: half, height: height)

        let aspect = (contentAspect.isFinite && contentAspect > 0) ? contentAspect : fallbackAspect
        let scale = CGFloat(s.screenScale)
        let maxWidth = half * scale
        let maxHeight = height * scale
        var screenWidth = maxWidth
        var screenHeight = aspect > 0 ? screenWidth / aspect : 0
        if screenHeight > maxHeight {
            screenHeight = maxHeight
            screenWidth = screenHeight * aspect
        }

        // Positiver Abstand schiebt beide Leinwände symmetrisch nach außen.
        let shift = CGFloat(s.horizontalSpacing) * half / 2
        let centerY = height / 2 + CGFloat(s.verticalOffset) * height / 2
        let leftCenterX = half / 2 - shift
        let rightCenterX = half + half / 2 + shift

        let leftScreen = CGRect(x: leftCenterX - screenWidth / 2, y: centerY - screenHeight / 2,
                                width: screenWidth, height: screenHeight)
        let rightScreen = CGRect(x: rightCenterX - screenWidth / 2, y: centerY - screenHeight / 2,
                                 width: screenWidth, height: screenHeight)
        return StereoLayout(leftEye: leftEye, rightEye: rightEye, leftScreen: leftScreen, rightScreen: rightScreen)
    }
}

nonisolated enum VideoGeometry {
    /// Sichtbarer Bildbereich eines Videos (object-fit: contain) innerhalb seines Elements.
    static func contentRect(element: CGRect, videoSize: CGSize) -> CGRect {
        guard element.width > 0, element.height > 0 else { return .zero }
        guard videoSize.width > 0, videoSize.height > 0 else { return element }
        let videoAspect = videoSize.width / videoSize.height
        let elementAspect = element.width / element.height
        if videoAspect > elementAspect {
            let h = element.width / videoAspect
            return CGRect(x: element.minX, y: element.midY - h / 2, width: element.width, height: h)
        } else {
            let w = element.height * videoAspect
            return CGRect(x: element.midX - w / 2, y: element.minY, width: w, height: element.height)
        }
    }
}

nonisolated enum FrameCropper {
    /// Wendet den manuellen Ausschnitt an. Das Ergebnis wird für beide Augen verwendet.
    static func crop(_ image: CGImage, settings: CalibrationSettings) -> CGImage {
        let crop = settings.effectiveCrop
        guard !crop.isFull else { return image }
        let rect = crop.pixelRect(width: image.width, height: image.height)
        guard rect.width >= 1, rect.height >= 1 else { return image }
        return image.cropping(to: rect) ?? image
    }
}
