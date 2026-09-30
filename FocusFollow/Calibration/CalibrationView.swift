import AppKit
import SwiftUI

struct CalibrationView: View {
    static let windowID = "calibration"

    let focus: FocusController
    let tracker: HeadTracker
    @Environment(\.dismissWindow) private var dismissWindow

    private var session: CalibrationSession { focus.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if focus.gridSession.isActive {
                GridProgressView(session: focus.gridSession)
            } else if focus.gridSession.phase == .finished {
                GridSummaryView(focus: focus)
            } else {
                switch session.phase {
                case .idle: intro
                case .settling, .collecting: progress
                case .finished: summary
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(WindowLevelSetter(level: .statusBar))
        .onDisappear {
            if session.isActive { session.cancel() }
            if focus.gridSession.phase != .idle { focus.gridSession.cancel() }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calibrate screens").font(.title2.bold())
            Text("FocusFollow will highlight each screen in turn. Look at the middle of the highlighted screen and keep your head still and natural for about \(Int(CalibrationSession.collectDuration)) seconds.")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(focus.layout.displays) { display in
                    Label(focus.layout.label(for: display.id), systemImage: "display")
                }
            }
            if tracker.status != .running {
                Text("The camera isn't running. Resume FocusFollow and make sure camera access is allowed.")
                    .foregroundStyle(.orange)
            }
            if let message = session.message {
                Text(message).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Start") { session.start(layout: focus.layout) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(tracker.status != .running || focus.layout.displays.isEmpty)
            }
            Divider()
            gridSection
        }
    }

    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Window focus (experimental)").font(.headline)
            Text("Look at a grid of dots on each calibrated screen so FocusFollow can estimate where on the screen you're looking. Takes about \(Int(Double(GridCalibrationSession.targets.count) * (GridCalibrationSession.settleDuration + GridCalibrationSession.collectDuration))) seconds per screen.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if focus.gridWasCleared {
                Text("Recalibrating screens cleared the gaze grid. Calibrate it again to use window focus.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if let message = focus.gridSession.message {
                Text(message).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Calibrate Gaze Grid") { focus.startGridCalibration() }
                    .disabled(tracker.status != .running || !focus.isCalibrated)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screen \(session.index + 1) of \(session.layout.displays.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let display = session.currentDisplay {
                Text(session.layout.label(for: display.id)).font(.title2.bold())
            }
            Text(statusLine)
            ProgressView(value: session.progress)
            if let message = session.message {
                Text(message).foregroundStyle(.orange)
            }
            HStack {
                Button("Cancel", role: .cancel) { session.cancel() }
                Spacer()
                Button("Back") { session.back() }
                    .disabled(session.index == 0)
                Button("Redo") { session.redo() }
                Button("Skip") { session.skip() }
            }
        }
    }

    private var statusLine: String {
        switch session.phase {
        case .settling: "Look at the highlighted screen…"
        case .collecting: session.faceVisible ? "Recording. Keep looking at the highlighted screen." : "No face detected. Face the camera."
        default: ""
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calibration saved").font(.title2.bold())
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                ForEach(session.completed) { screen in
                    GridRow {
                        Text(screen.name)
                        Text(String(format: "yaw %+.1f° ± %.1f", screen.stats.meanYaw, screen.stats.stdYaw))
                        Text(String(format: "pitch %+.1f° ± %.1f", screen.stats.meanPitch, screen.stats.stdPitch))
                    }
                }
            }
            .font(.system(.caption, design: .monospaced))
            if session.completed.count < session.layout.displays.count {
                Text("Some screens were skipped and won't be recognized.").foregroundStyle(.orange)
            }
            HStack {
                Button("Recalibrate") { session.start(layout: focus.layout) }
                Spacer()
                Button("Done") {
                    session.cancel()
                    dismissWindow(id: Self.windowID)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Raises the hosting window above the calibration overlay so its buttons stay visible.
private struct WindowLevelSetter: NSViewRepresentable {
    let level: NSWindow.Level

    func makeNSView(context: Context) -> LevelView {
        let view = LevelView()
        view.level = level
        return view
    }

    func updateNSView(_ view: LevelView, context: Context) {
        view.level = level
    }

    final class LevelView: NSView {
        var level = NSWindow.Level.normal {
            didSet { window?.level = level }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.level = level
        }
    }
}
