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
    @State private var observationVisible = false

    private var frame: VideoFrame? {
        switch source {
        case .reference: return model.reference.frame
        case .youtube: return model.snapshot.latest
        case .youtubeMirror, .localVideoMirror: return nil
        }
    }

    private var counterText: String {
        if source.isMirror {
            // Nur Information: Die Player-Zeit belegt keine sichtbare Wiedergabe.
            let status = model.player.status
            return "Player-Zeit \(TimeFormatter.clock(status.currentTime)) (\(status.isPaused ? "pausiert" : "läuft")) · \(model.mirrorTest.mode.title)"
        }
        return "Frame \(frame?.sequence ?? 0)"
    }

    var body: some View {
        ZStack {
            Color.black

            if source.isMirror {
                // Keine SwiftUI-Geste über der WebView: Die Leiste wird über die Eck-Taste gesteuert.
                MirrorCinemaView(player: model.player,
                                 settings: model.calibration.settings,
                                 mode: model.mirrorTest.mode,
                                 status: model.player.status,
                                 onGeometry: { geometry in
                                     model.mirrorTest.updateGeometry(geometry)
                                     model.mirrorTest.updateCalibration(model.calibration.settings)
                                 })
                    .accessibilityIdentifier("cardboard.mirror")
                HalfLabels(mode: model.mirrorTest.mode)
            } else {
                StereoCinemaView(frame: frame, settings: model.calibration.settings)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleControls() }
                    .accessibilityElement()
                    .accessibilityLabel("Stereo-Leinwand, Frame \(frame?.sequence ?? 0)")
                    .accessibilityIdentifier("cardboard.stereo")
            }

            if source == .youtube {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    healthOverlay
                }
            }

            if source.isMirror && observationVisible {
                MirrorObservationPanel(
                    onClose: { observationVisible = false },
                    onReport: { model.exitCardboard(then: .mirrorTest) },
                    onExit: { model.exitCardboard() }
                )
            }

            if !controlsVisible {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation { controlsVisible = true }
                            scheduleHide()
                        } label: {
                            Image(systemName: "ellipsis.circle.fill")
                                .font(.title2)
                                .padding(10)
                        }
                        .accessibilityLabel("Bedienleiste einblenden")
                        .accessibilityIdentifier("cardboard.showControls")
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.trailing, 16)
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
                Text(counterText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("cardboard.frameCounter")
            }

            Spacer()

            if source.isMirror {
                Button {
                    observationVisible.toggle()
                } label: {
                    Label("Beobachtung", systemImage: "eye")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("cardboard.observation")
            }

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

            Button {
                hideTask?.cancel()
                withAnimation { controlsVisible = false }
            } label: {
                Label("Ausblenden", systemImage: "chevron.up")
            }
            .buttonStyle(.bordered)
            .labelStyle(.iconOnly)
            .accessibilityIdentifier("cardboard.hideControls")
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
        // Im Spiegeltest bleibt die Leiste, bis sie bewusst ausgeblendet wird.
        if source.isMirror { return }
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, !calibrationVisible else { return }
            withAnimation { controlsVisible = false }
        }
    }
}

/// Eindeutige, NICHT replizierte Beschriftung der Bildschirmhälften (SwiftUI-Ebene über dem Spiegel).
private struct HalfLabels: View {
    let mode: MirrorDisplayMode

    var body: some View {
        HStack(spacing: 0) {
            label(left: true)
            label(left: false)
        }
        .allowsHitTesting(false)
    }

    private func label(left: Bool) -> some View {
        Text("\(left ? "LINKE HÄLFTE" : "RECHTE HÄLFTE") · \(mode.role(leftHalf: left))")
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(left ? Color.orange.opacity(0.85) : Color.cyan.opacity(0.85), in: Capsule())
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 10)
            .accessibilityIdentifier(left ? "cardboard.half.left" : "cardboard.half.right")
    }
}

/// Manuelle Sichtprüfung je Bildschirmhälfte für den laufenden Spiegel-Durchlauf.
private struct MirrorObservationPanel: View {
    @Environment(AppModel.self) private var model
    let onClose: () -> Void
    let onReport: () -> Void
    let onExit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("Manuelle Beobachtung – was siehst du in jeder Hälfte? (Die Player-Zeit zählt nicht als Nachweis.)")
                .font(.caption.bold())
                .multilineTextAlignment(.center)
            if let run = model.mirrorTest.currentRun {
                HStack(alignment: .top, spacing: 12) {
                    MirrorObservationColumn(run: run, leftHalf: true)
                    MirrorObservationColumn(run: run, leftHalf: false)
                }
            }
            HStack {
                Button("Schließen", action: onClose)
                    .buttonStyle(.bordered)
                Button("Bericht", action: onReport)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("cardboard.observation.report")
                Button("Zum Player", action: onExit)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("cardboard.observation.exit")
            }
        }
        .padding(14)
        .frame(maxWidth: 620)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("cardboard.observation.panel")
    }
}

/// Auswahl für eine Bildschirmhälfte (auch in der Testübersicht verwendet).
struct MirrorObservationColumn: View {
    @Environment(AppModel.self) private var model
    let run: MirrorTestRun
    let leftHalf: Bool

    var body: some View {
        let half = leftHalf ? run.left : run.right
        VStack(alignment: .leading, spacing: 6) {
            Text("\(leftHalf ? "LINKS" : "RECHTS") · \(run.mode.role(leftHalf: leftHalf))")
                .font(.caption.bold())
                .foregroundStyle(leftHalf ? Color.orange : Color.cyan)
            Picker("Video \(leftHalf ? "links" : "rechts")", selection: Binding(
                get: { half.video },
                set: { model.mirrorTest.setObservation(runID: run.id, leftHalf: leftHalf, video: $0) }
            )) {
                ForEach(VideoObservation.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier(leftHalf ? "obs.left.video" : "obs.right.video")
            Picker("Oberfläche \(leftHalf ? "links" : "rechts")", selection: Binding(
                get: { half.overlay },
                set: { model.mirrorTest.setObservation(runID: run.id, leftHalf: leftHalf, overlay: $0) }
            )) {
                ForEach(OverlayObservation.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier(leftHalf ? "obs.left.overlay" : "obs.right.overlay")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
