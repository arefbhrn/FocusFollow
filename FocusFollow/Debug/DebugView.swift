import AVFoundation
import SwiftUI

struct DebugView: View {
    static let windowID = "debug"

    @Bindable var tracker: HeadTracker
    let focus: FocusController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
            .frame(width: 480, height: 270)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(alignment: .top, spacing: 24) {
                PoseReadout(tracker: tracker)
                Spacer()
                PosePad(pose: tracker.pose)
            }

            FocusReadout(focus: focus)

            GazeMapView(focus: focus)

            VStack(alignment: .leading, spacing: 4) {
                Text("Smoothing: \(tracker.smoothing, format: .number.precision(.fractionLength(2)))")
                Slider(value: $tracker.smoothing, in: 0.05...1) {
                    EmptyView()
                } minimumValueLabel: {
                    Text("Smooth")
                } maximumValueLabel: {
                    Text("Fast")
                }
            }
            .font(.caption)
        }
        .padding(20)
        .frame(width: 520)
    }
}

private struct StatusMessage: View {
    let status: HeadTracker.Status

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            if status == .permissionDenied {
                Button("Open Camera Settings") {
                    CameraPermission.openSettings()
                }
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Focus").bold()
            Text("Accessibility: \(focus.accessibilityTrusted ? "granted" : "not granted")")
            Text("Switching: \(focus.holdReason?.label ?? "free")")
            if FocusSettings.windowFocus {
                Text("Window under gaze: \(focus.targetWindowLabel ?? "—")")
            }
            if focus.calibration == nil {
                Text("Not calibrated for this display setup")
            } else if let evaluation = focus.evaluation {
                Text("Now: \(focus.label(for: evaluation.result))")
                Text("Confirmed: \(focus.confirmed.map { focus.label(for: $0) } ?? "—")")
                Grid(alignment: .trailing, horizontalSpacing: 16, verticalSpacing: 2) {
                    ForEach(evaluation.distances.sorted { $0.key < $1.key }, id: \.key) { entry in
                        GridRow {
                            Text(focus.layout.label(for: entry.key))
                                .gridColumnAlignment(.leading)
                            Text(entry.value, format: .number.precision(.fractionLength(2)))
                        }
                    }
                }
            } else {
                Text("No face")
            }
        }
        .font(.system(.caption, design: .monospaced))
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
        .font(.system(.body, design: .monospaced))
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
            RoundedRectangle(cornerRadius: 6)
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
                    .fill(.green)
                    .frame(width: 10, height: 10)
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
            Text("Gaze map").bold()
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
