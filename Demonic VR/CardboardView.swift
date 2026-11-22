//
//  CardboardView.swift
//  Demonic VR
//
//  Querformat, zwei Augenbereiche, flache Kinoleinwand. Beide Augen werden
//  in EINEM Canvas-Durchgang aus demselben VideoFrame gezeichnet – sie zeigen
//  daher immer exakt denselben Frame, auch bei Pufferung oder Aussetzern.
//

import CoreGraphics
import QuartzCore
import SwiftUI
import UIKit

struct CardboardView: View {
    @Environment(AppModel.self) private var model
    let source: CardboardSource

    @State private var controlsVisible = true
    @State private var calibrationVisible = false
    @State private var hideTask: Task<Void, Never>?

    private var frame: VideoFrame? {
        switch source {
        case .reference: return model.reference.frame
        case .youtube: return model.snapshot.latest
        }
    }

    var body: some View {
        ZStack {
            Color.black

            StereoCinemaView(frame: frame, settings: model.calibration.settings)
                .contentShape(Rectangle())
                .onTapGesture { toggleControls() }
                .accessibilityElement()
                .accessibilityLabel("Stereo-Leinwand, Frame \(frame?.sequence ?? 0)")
                .accessibilityIdentifier("cardboard.stereo")

            if source == .youtube {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    healthOverlay
                }
            }

            if controlsVisible {
                VStack {
                    controlBar
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if calibrationVisible {
                HStack {
                    Spacer()
                    ScrollView {
                        CalibrationControls(compact: true)
                            .padding(14)
                    }
                    .frame(width: 340)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(.vertical, 12)
                    .padding(.trailing, 12)
                }
                .transition(.move(edge: .trailing))
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cardboard.view")
        .onAppear {
            OrientationController.lockLandscape()
            UIApplication.shared.isIdleTimerDisabled = true
            model.startFrameSource(source)
            scheduleHide()
        }
        .onDisappear {
            hideTask?.cancel()
            model.stopFrameSource(source)
            UIApplication.shared.isIdleTimerDisabled = false
            OrientationController.unlock()
        }
    }

    // MARK: - Bedienleiste

    private var controlBar: some View {
        HStack(spacing: 12) {
            Button {
                model.exitCardboard()
            } label: {
                Label("Zurück zum Player", systemImage: "chevron.backward")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("cardboard.exit")

            VStack(alignment: .leading, spacing: 0) {
                Text(source.title).font(.subheadline.bold())
                Text("Frame \(frame?.sequence ?? 0)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cardboard.frameCounter")
            }

            Spacer()

            if source == .reference {
                Toggle("Aussetzer", isOn: Binding(
                    get: { model.reference.simulateDropouts },
                    set: { model.reference.simulateDropouts = $0 }
                ))
                .toggleStyle(.button)
                .accessibilityIdentifier("cardboard.dropouts")
            }

            Button {
                withAnimation { calibrationVisible.toggle() }
                scheduleHide()
            } label: {
                Label("Kalibrierung", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("cardboard.calibration")

            Button {
                model.exitCardboard(then: .diagnostics)
            } label: {
                Label("Diagnose", systemImage: "waveform.path.ecg")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("cardboard.diagnostics")
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 12)
        .padding(.horizontal, 24)
    }

    // MARK: - Zustand der YouTube-Quelle

    @ViewBuilder
    private var healthOverlay: some View {
        let health = CardboardGate.health(model.snapshot.stats, at: CACurrentMediaTime())
        switch health {
        case .ok:
            EmptyView()
        case .warmingUp:
            Text("Warte auf Frames …")
                .font(.caption)
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())
        default:
            StreamProblemPanel(message: health.message,
                               onDiagnostics: { model.exitCardboard(then: .diagnostics) },
                               onExit: { model.exitCardboard() })
        }
    }

    private func toggleControls() {
        withAnimation { controlsVisible.toggle() }
        if controlsVisible { scheduleHide() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard !model.environment.isUITest else { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, !calibrationVisible else { return }
            withAnimation { controlsVisible = false }
        }
    }
}

/// Bleibt bei schwarzem oder eingefrorenem Bild sichtbar und bedienbar.
private struct StreamProblemPanel: View {
    let message: String
    let onDiagnostics: () -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Label("YouTube-Bild nicht nutzbar", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            HStack {
                Button("Diagnose", action: onDiagnostics)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("cardboard.problem.diagnostics")
                Button("Zurück zum Player", action: onExit)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("cardboard.problem.exit")
            }
        }
        .padding(18)
        .frame(maxWidth: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Stereo-Leinwand

struct StereoCinemaView: View {
    let frame: VideoFrame?
    let settings: CalibrationSettings

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

            let half = size.width / 2
            var divider = Path()
            divider.move(to: CGPoint(x: half, y: 0))
            divider.addLine(to: CGPoint(x: half, y: size.height))
            context.stroke(divider, with: .color(.white.opacity(0.25)), lineWidth: 1)

            guard let frame else {
                let waiting = context.resolve(Text("Warte auf Bild …").font(.caption).foregroundStyle(.white.opacity(0.7)))
                context.draw(waiting, at: CGPoint(x: half / 2, y: size.height / 2))
                context.draw(waiting, at: CGPoint(x: half * 1.5, y: size.height / 2))
                return
            }

            // Einmal zuschneiden, einmal auflösen – dasselbe Bildobjekt für beide Augen.
            let cropped = FrameCropper.crop(frame.image, settings: settings)
            let aspect = CGFloat(cropped.width) / CGFloat(max(cropped.height, 1))
            let layout = StereoLayout.compute(container: size, contentAspect: aspect, settings: settings)
            let image = context.resolve(Image(decorative: cropped, scale: 1))
            let label = context.resolve(
                Text("#\(frame.sequence)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
            )

            for (screen, eye) in [(layout.leftScreen, layout.leftEye), (layout.rightScreen, layout.rightEye)] {
                context.drawLayer { layer in
                    layer.clip(to: Path(eye))
                    layer.draw(image, in: screen)
                    let labelY = min(screen.maxY + 12, eye.maxY - 10)
                    layer.draw(label, at: CGPoint(x: screen.midX, y: labelY), anchor: .center)
                }
            }
        }
    }
}
