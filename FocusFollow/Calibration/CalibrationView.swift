import AppKit
import SwiftUI

struct CalibrationView: View {
    static let windowID = "calibration"

    let focus: FocusController
    let tracker: HeadTracker
    @Environment(\.dismissWindow) private var dismissWindow

    private var session: CalibrationSession { focus.session }
    private var gridSession: GridCalibrationSession { focus.gridSession }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            if gridSession.isActive {
                GridProgressView(session: gridSession)
            } else if gridSession.phase == .finished {
                GridSummaryView(focus: focus)
            } else {
                switch session.phase {
                case .idle: intro
                case .settling, .collecting: progress
                case .finished: summary
                }
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 480)
        .background(WindowLevelSetter(level: .statusBar))
        .onDisappear {
            if session.isActive { session.cancel() }
            if gridSession.phase != .idle { gridSession.cancel() }
        }
    }

    // MARK: - Intro

    private var intro: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            WindowHeader(symbol: "viewfinder", title: "Calibrate", subtitle: "Teach FocusFollow where your screens are. It only takes a minute.")

            if let problem = cameraProblem {
                Banner(kind: .warning, text: problem.text) {
                    if problem.opensCameraSettings {
                        Button("Open Camera Settings") { CameraPermission.openSettings() }
                            .controlSize(.small)
                    }
                }
            }

            StepCard(
                number: 1,
                title: "Screens",
                detail: "Look at the middle of each highlighted screen for about \(Int(CalibrationSession.collectDuration)) seconds, head still and natural."
            ) {
                ForEach(focus.layout.displays) { display in
                    HStack {
                        Label(focus.layout.label(for: display.id), systemImage: "display")
                        Spacer()
                        CalibrationPill(calibrated: focus.isCalibrated(display.id))
                    }
                    .font(.callout)
                }
                if let message = session.message {
                    StatusLabel(kind: .warning, text: message).font(.callout)
                }
                HStack {
                    Spacer()
                    Button("Calibrate Screens") { session.start(layout: focus.layout) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                        .disabled(tracker.status != .running || focus.layout.displays.isEmpty)
                }
            }

            StepCard(
                number: 2,
                title: "Gaze grid",
                badge: "Optional · experimental",
                detail: "Look at a grid of dots on each screen so FocusFollow can tell where on the screen you're looking. Takes about \(gridSeconds) seconds per screen."
            ) {
                if focus.gridWasCleared {
                    StatusLabel(kind: .warning, text: "Recalibrating screens cleared the gaze grid. Calibrate it again to use window focus.")
                        .font(.callout)
                }
                if let message = gridSession.message {
                    StatusLabel(kind: .warning, text: message).font(.callout)
                }
                HStack {
                    if !focus.isCalibrated {
                        Text("Calibrate your screens first.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Calibrate Gaze Grid") { focus.startGridCalibration() }
                        .controlSize(.large)
                        .disabled(tracker.status != .running || !focus.isCalibrated)
                }
            }
        }
    }

    private var gridSeconds: Int {
        Int(Double(GridCalibrationSession.targets.count) * (GridCalibrationSession.settleDuration + GridCalibrationSession.collectDuration))
    }

    /// Why calibration can't start yet, if it can't.
    private var cameraProblem: (text: String, opensCameraSettings: Bool)? {
        switch tracker.status {
        case .running: nil
        case .permissionDenied: ("FocusFollow can't use the camera. Allow it in System Settings → Privacy & Security → Camera.", true)
        case .noCamera: ("No camera found. Connect one to calibrate.", false)
        case .failed(let error): ("Camera error: \(error)", false)
        case .stopped, .requestingPermission: ("The camera isn't running. Resume FocusFollow from the menu bar to calibrate.", false)
        }
    }

    // MARK: - Screen calibration progress

    private var progress: some View {
        VStack(spacing: Theme.Space.l) {
            Text("Screen \(session.index + 1) of \(session.layout.displays.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressRing(
                progress: session.progress,
                label: "Calibrating screen \(session.index + 1) of \(session.layout.displays.count)"
            ) {
                Image(systemName: session.faceVisible || session.phase == .settling ? "viewfinder" : "person.fill.questionmark")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.brandGradient)
            }
            .frame(width: 132, height: 132)
            if let display = session.currentDisplay {
                Text(session.layout.label(for: display.id)).font(.title3.weight(.semibold))
            }
            StatusLabel(kind: statusLine.kind, text: statusLine.text, secondary: statusLine.kind != .warning)
                .multilineTextAlignment(.center)
            if let message = session.message {
                StatusLabel(kind: .warning, text: message).font(.callout)
            }
            HStack {
                Button("Cancel", role: .cancel) { session.cancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Back") { session.back() }
                    .disabled(session.index == 0)
                Button("Redo") { session.redo() }
                Button("Skip") { session.skip() }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statusLine: (text: String, kind: Theme.Status) {
        switch session.phase {
        case .settling: ("Look at the highlighted screen…", .neutral)
        case .collecting:
            session.faceVisible
                ? ("Recording. Keep looking at the highlighted screen.", .ok)
                : ("No face detected. Face the camera.", .warning)
        default: ("", .neutral)
        }
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            WindowHeader(symbol: "checkmark.seal.fill", title: "Calibration saved", subtitle: "FocusFollow will now follow your head between these screens.", tint: .green)
            Card(padding: Theme.Space.m) {
                VStack(spacing: Theme.Space.s) {
                    ForEach(session.completed) { screen in
                        HStack(alignment: .firstTextBaseline) {
                            Text(screen.name)
                            Spacer()
                            Text(String(format: "yaw %+.0f° · pitch %+.0f°", screen.stats.meanYaw, screen.stats.meanPitch))
                                .font(.system(.caption, design: .rounded).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if screen.id != session.completed.last?.id { Divider() }
                    }
                }
            }
            if session.completed.count < session.layout.displays.count {
                Banner(kind: .warning, text: "Some screens were skipped and won't be recognized.")
            }
            HStack {
                Button("Recalibrate") { session.start(layout: focus.layout) }
                Spacer()
                Button("Done") {
                    session.cancel()
                    dismissWindow(id: Self.windowID)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Pieces

/// An icon badge with a title and a one-line explanation at the top of a window.
struct WindowHeader: View {
    let symbol: String
    let title: String
    let subtitle: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            IconBadge(symbol: symbol, tint: tint, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A coloured note with an icon, for things that stop the user from continuing.
struct Banner<Actions: View>: View {
    let kind: Theme.Status
    let text: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text(text).font(.callout)
                actions
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.m)
        .background(kind.color.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

extension Banner where Actions == EmptyView {
    init(kind: Theme.Status, text: String) {
        self.init(kind: kind, text: text) { EmptyView() }
    }
}

/// A numbered card for one stage of a multi-step task.
struct StepCard<Content: View>: View {
    let number: Int
    let title: String
    var badge: String?
    let detail: String
    @ViewBuilder var content: Content

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.s) {
                    Text("\(number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Theme.brandGradient, in: Circle())
                        .accessibilityHidden(true)
                    Text(title).font(.headline)
                    if let badge {
                        Text(badge)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.Space.s)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
        }
    }
}

struct CalibrationPill: View {
    let calibrated: Bool

    var body: some View {
        StatusLabel(kind: calibrated ? .ok : .neutral, text: calibrated ? "Calibrated" : "Not calibrated", secondary: true)
            .font(.caption)
    }
}

/// A circular progress indicator with content in the middle. Skips the animation when Reduce Motion is on.
struct ProgressRing<Center: View>: View {
    let progress: Double
    /// What VoiceOver reads; the centre content is decorative to it.
    var label = "Progress"
    var valueText: String?
    @ViewBuilder var center: Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.1), lineWidth: 8)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Theme.brandGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.1), value: progress)
            center
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(valueText ?? "\(Int(progress * 100)) percent")
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
