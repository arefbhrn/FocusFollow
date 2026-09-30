import AVFoundation
import SwiftUI

struct DebugView: View {
    static let windowID = "debug"

    @Bindable var tracker: HeadTracker
    let focus: FocusController

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            WindowHeader(symbol: "waveform.path.ecg", title: "Diagnostics", subtitle: "See what FocusFollow sees. Useful for checking your setup and calibration.")

            CameraPicker(tracker: tracker)

            ZStack {
                Color.black
                if tracker.status == .running {
                    CameraPreview(session: tracker.session, cameraID: tracker.activeCameraID)
                    FaceBoxOverlay(box: tracker.faceBox, imageSize: tracker.imageSize)
                } else {
                    StatusMessage(status: tracker.status)
                }
            }
            .frame(height: 270)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
            .accessibilityLabel("Camera preview")

            HStack(alignment: .top, spacing: Theme.Space.m) {
                Card(padding: Theme.Space.m) { PoseReadout(tracker: tracker) }
                Card(padding: Theme.Space.m) {
                    VStack(spacing: Theme.Space.s) {
                        PosePad(pose: tracker.pose)
                        Text("Head direction").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(width: 168)
            }

            Card { FocusReadout(focus: focus) }

            Card { GazeMapView(focus: focus) }

            Card(padding: Theme.Space.m) {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    HStack {
                        Text("Smoothing").font(.callout)
                        Spacer()
                        Text(tracker.smoothing, format: .number.precision(.fractionLength(2)))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $tracker.smoothing, in: 0.05...1) {
                        Text("Smoothing")
                    } minimumValueLabel: {
                        Text("Smooth").font(.caption)
                    } maximumValueLabel: {
                        Text("Fast").font(.caption)
                    }
                    .labelsHidden()
                    Text("Smoother reacts more slowly. Faster reacts to every small movement.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 560)
    }
}

private struct StatusMessage: View {
    let status: HeadTracker.Status

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: "video.slash")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            if status == .permissionDenied {
                Button("Open Camera Settings") {
                    CameraPermission.openSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private var message: String {
        switch status {
        case .stopped: "Tracking is paused."
        case .requestingPermission: "Waiting for camera permission…"
        case .permissionDenied: "FocusFollow can't use the camera.\nAllow it in System Settings → Privacy & Security → Camera."
        case .noCamera: "No camera found. Connect one to start tracking."
        case .running: ""
        case .failed(let error): "Camera error: \(error)"
        }
    }
}

/// Draws the detected face box over the mirrored, aspect-fit preview.
private struct FaceBoxOverlay: View {
    let box: CGRect?
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            if let box, imageSize.width > 0, imageSize.height > 0 {
                let fitted = aspectFit(imageSize, in: geometry.size)
                // Vision: normalized, origin bottom-left. Preview is mirrored horizontally.
                let rect = CGRect(
                    x: fitted.minX + (1 - box.maxX) * fitted.width,
                    y: fitted.minY + (1 - box.maxY) * fitted.height,
                    width: box.width * fitted.width,
                    height: box.height * fitted.height
                )
                Rectangle()
                    .stroke(.green, lineWidth: 2)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }

    private func aspectFit(_ size: CGSize, in container: CGSize) -> CGRect {
        let scale = min(container.width / size.width, container.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: (container.width - fitted.width) / 2,
            y: (container.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}

private struct FocusReadout: View {
    let focus: FocusController

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Focus").font(.headline)
            StatusRow(
                symbol: "hand.raised",
                title: "Accessibility",
                status: focus.accessibilityTrusted ? .ok : .warning,
                detail: focus.accessibilityTrusted ? "Allowed" : "Not allowed"
            )
            StatusRow(
                symbol: "arrow.left.arrow.right",
                title: "Switching",
                status: focus.holdReason == nil ? .ok : .neutral,
                detail: focus.holdReason?.label ?? "Ready"
            )
            if FocusSettings.windowFocus {
                StatusRow(
                    symbol: "macwindow",
                    title: "Window under gaze",
                    status: focus.targetWindowLabel == nil ? .neutral : .ok,
                    detail: focus.targetWindowLabel ?? "None"
                )
            }
            Divider()
            if focus.calibration == nil {
                Label("Not calibrated for this display setup", systemImage: Theme.Status.warning.symbol)
                    .foregroundStyle(Theme.Status.warning.color)
                    .font(.callout)
            } else if let evaluation = focus.evaluation {
                LabeledContent("Now") { Text(focus.label(for: evaluation.result)) }
                LabeledContent("Confirmed") { Text(focus.confirmed.map { focus.label(for: $0) } ?? "—") }
                Grid(alignment: .trailing, horizontalSpacing: Theme.Space.l, verticalSpacing: 2) {
                    ForEach(evaluation.distances.sorted { $0.key < $1.key }, id: \.key) { entry in
                        GridRow {
                            Text(focus.layout.label(for: entry.key))
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.leading)
                            Text(entry.value, format: .number.precision(.fractionLength(2)))
                                .monospacedDigit()
                        }
                    }
                }
                .font(.caption)
            } else {
                Label("No face in view", systemImage: Theme.Status.neutral.symbol)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PoseReadout: View {
    let tracker: HeadTracker

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Text("")
                Text("Smoothed").bold()
                Text("Raw").foregroundStyle(.secondary)
            }
            row("Yaw", \.yaw)
            row("Pitch", \.pitch)
            row("Roll", \.roll)
            Divider()
            GridRow {
                Text("Face")
                Text(tracker.pose == nil ? "—" : "Detected")
                    .gridCellColumns(2)
                    .gridCellAnchor(.leading)
            }
            GridRow {
                Text("FPS")
                Text(tracker.framesPerSecond, format: .number.precision(.fractionLength(1)))
                    .gridCellColumns(2)
                    .gridCellAnchor(.leading)
            }
        }
        .font(.system(.callout, design: .rounded).monospacedDigit())
    }

    private func row(_ label: String, _ angle: KeyPath<HeadPose, Double>) -> some View {
        GridRow {
            Text(label)
            Text(format(tracker.pose?[keyPath: angle]))
            Text(format(tracker.rawPose?[keyPath: angle]))
                .foregroundStyle(.secondary)
        }
    }

    private func format(_ degrees: Double?) -> String {
        guard let degrees else { return "—" }
        return String(format: "%+6.1f°", degrees)
    }
}

/// Yaw / pitch as a dot, ±45° across the pad.
private struct PosePad: View {
    let pose: HeadPose?
    private let range = 45.0
    private let size = 120.0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.s)
                .stroke(.secondary.opacity(0.5))
            Path { path in
                path.move(to: CGPoint(x: size / 2, y: 0))
                path.addLine(to: CGPoint(x: size / 2, y: size))
                path.move(to: CGPoint(x: 0, y: size / 2))
                path.addLine(to: CGPoint(x: size, y: size / 2))
            }
            .stroke(.secondary.opacity(0.3))
            if let pose {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                    .position(point(for: pose))
            }
        }
        .frame(width: size, height: size)
    }

    private func point(for pose: HeadPose) -> CGPoint {
        func clamp(_ value: Double) -> Double { min(max(value / range, -1), 1) }
        return CGPoint(
            x: size / 2 * (1 + clamp(pose.yaw)),
            y: size / 2 * (1 - clamp(pose.pitch))
        )
    }
}

/// The classified screen as a rectangle, with the grid targets and the live gaze estimate.
private struct GazeMapView: View {
    let focus: FocusController
    private let width = 240.0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gaze map").font(.headline)
            if let gaze = focus.gaze, let display = focus.layout.display(withID: gaze.displayID) {
                GridQualityMap(
                    grid: targets(for: display.id),
                    model: focus.gazeModels[display.id],
                    aspect: display.bounds.width / max(display.bounds.height, 1),
                    width: width,
                    gaze: CGPoint(x: gaze.x, y: gaze.y)
                )
                Text("\(focus.layout.label(for: display.id)) · typical error \(focus.gazeModels[display.id]?.gateError ?? 0, format: .percent.precision(.fractionLength(0)))\(droppedText(for: display.id))")
                    .foregroundStyle(.secondary)
                GridQualityLegend()
            } else if focus.gazeModels.isEmpty {
                Text("No gaze grid yet. Use Calibrate → Calibrate Gaze Grid.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Look at a screen with a gaze grid.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func targets(for id: String) -> [GridSample] {
        focus.calibration?.screens.first { $0.id == id }?.grid ?? []
    }

    private func droppedText(for id: String) -> String {
        let count = focus.gazeModels[id]?.droppedIndices.count ?? 0
        return count == 0 ? "" : " · \(count) dots ignored"
    }
}
