import AppKit
import Observation
import OSLog
import SwiftUI

/// Shows a dot at each point of a 5×5 grid on every calibrated screen and records the head pose for each.
@MainActor
@Observable
final class GridCalibrationSession {
    enum Phase: Equatable {
        case idle
        case settling
        case collecting
        case finished
    }

    /// Margins keep the outer targets off the very edge of the screen, where people stop turning their head.
    /// Rows alternate direction so the next dot is always next to the last one.
    private static let gridPositions: [Double] = [0.12, 0.31, 0.5, 0.69, 0.88]
    static let targets: [CGPoint] = gridPositions.enumerated().flatMap { row, y in
        (row.isMultiple(of: 2) ? gridPositions : gridPositions.reversed()).map { CGPoint(x: $0, y: y) }
    }
    static let settleDuration: TimeInterval = 0.9
    static let collectDuration: TimeInterval = 1.2
    static let minimumSamples = 6
    private static let tickInterval = Duration.milliseconds(66)
    private static let logger = Logger(subsystem: "com.arefbhrn.focusfollow", category: "grid-calibration")

    private(set) var phase = Phase.idle
    private(set) var displays: [DisplayInfo] = []
    private(set) var layout = DisplayLayout(displays: [])
    private(set) var displayIndex = 0
    private(set) var targetIndex = 0
    private(set) var faceVisible = false
    private(set) var message: String?
    /// Samples per display ID, filled as the run goes.
    private(set) var results: [String: [GridSample]] = [:]

    /// Called once when a run finishes.
    @ObservationIgnored var onFinish: (@MainActor ([String: [GridSample]]) -> Void)?

    @ObservationIgnored private let tracker: HeadTracker
    @ObservationIgnored private let overlay = GridOverlay()
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var poses: [HeadPose] = []
    @ObservationIgnored private var elapsed: TimeInterval = 0
    @ObservationIgnored private var lastTick: TimeInterval = 0
    @ObservationIgnored private var escapeMonitors: [Any] = []

    init(tracker: HeadTracker) {
        self.tracker = tracker
    }

    var isActive: Bool {
        phase == .settling || phase == .collecting
    }

    var currentDisplay: DisplayInfo? {
        displays.indices.contains(displayIndex) ? displays[displayIndex] : nil
    }

    /// 0...1 over every target on every screen.
    var progress: Double {
        let total = displays.count * Self.targets.count
        guard total > 0 else { return 0 }
        let done = displayIndex * Self.targets.count + targetIndex
        return min(Double(done) / Double(total), 1)
    }

    func start(displays: [DisplayInfo], layout: DisplayLayout) {
        cancel()
        guard !displays.isEmpty else {
            message = "Calibrate your screens first."
            return
        }
        self.displays = displays
        self.layout = layout
        results = [:]
        displayIndex = 0
        targetIndex = 0
        beginTarget()
        startLoop()
    }

    func cancel() {
        stopLoop()
        overlay.hide()
        phase = .idle
        results = [:]
        message = nil
    }

    private func beginTarget(keepingMessage: Bool = false) {
        phase = .settling
        poses = []
        elapsed = 0
        faceVisible = false
        if !keepingMessage { message = nil }
        lastTick = ProcessInfo.processInfo.systemUptime
        guard let display = currentDisplay else { return }
        let target = Self.targets[targetIndex]
        overlay.model.point = target
        overlay.model.title = layout.label(for: display.id)
        overlay.model.detail = "Look at the dot (\(targetIndex + 1) of \(Self.targets.count))"
        overlay.model.progress = progress
        overlay.show(on: display)
    }

    /// The overlay is click-through, so Esc is the way out while it covers the window's Cancel button.
    private func installEscapeMonitors() {
        guard escapeMonitors.isEmpty else { return }
        let escapeKeyCode: UInt16 = 53
        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            MainActor.assumeIsolated {
                if code == escapeKeyCode { self?.cancel() }
            }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            MainActor.assumeIsolated {
                if code == escapeKeyCode { self?.cancel() }
            }
            return event
        }
        escapeMonitors = [global, local].compactMap { $0 }
    }

    private func removeEscapeMonitors() {
        escapeMonitors.forEach(NSEvent.removeMonitor)
        escapeMonitors = []
    }

    private func startLoop() {
        installEscapeMonitors()
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: Self.tickInterval)
            }
        }
    }

    private func stopLoop() {
        removeEscapeMonitors()
        loopTask?.cancel()
        loopTask = nil
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - lastTick, 0.5)
        lastTick = now

        switch phase {
        case .settling:
            elapsed += dt
            if elapsed >= Self.settleDuration {
                phase = .collecting
                elapsed = 0
                faceVisible = tracker.rawPose != nil
            }
        case .collecting:
            // Raw, not smoothed: the smoothed pose still lags toward the previous target.
            if let pose = tracker.rawPose {
                faceVisible = true
                if pose != poses.last { poses.append(pose) }
                elapsed += dt
            } else {
                faceVisible = false
                overlay.model.detail = "No face detected"
            }
            if faceVisible { overlay.model.detail = "Keep looking at the dot" }
            if elapsed >= Self.collectDuration { completeTarget() }
        case .idle, .finished:
            break
        }
    }

    private func completeTarget() {
        guard let display = currentDisplay else { return }
        guard poses.count >= Self.minimumSamples else {
            message = "Not enough samples. Trying this point again."
            beginTarget(keepingMessage: true)
            return
        }
        let target = Self.targets[targetIndex]
        results[display.id, default: []].append(GridSample(
            x: target.x,
            y: target.y,
            // Median, so a blink or a stray frame inside the dot's window doesn't drag the sample.
            yaw: GazeModel.median(poses.map(\.yaw)),
            pitch: GazeModel.median(poses.map(\.pitch))
        ))
        advance()
    }

    private func advance() {
        if targetIndex + 1 < Self.targets.count {
            targetIndex += 1
        } else if displayIndex + 1 < displays.count {
            displayIndex += 1
            targetIndex = 0
        } else {
            finish()
            return
        }
        beginTarget()
    }

    private func finish() {
        stopLoop()
        overlay.hide()
        displayIndex = displays.count
        targetIndex = 0
        phase = .finished
        Self.logger.info("Grid calibration finished for \(self.results.count) screens")
        onFinish?(results)
    }
}

@MainActor
@Observable
final class GridOverlayModel {
    /// 0...1 from the top-left of the screen.
    var point = CGPoint(x: 0.5, y: 0.5)
    var title = ""
    var detail = ""
    var progress = 0.0
}

/// A click-through panel covering one screen with a single target dot.
@MainActor
final class GridOverlay {
    let model = GridOverlayModel()
    private var panel: NSPanel?

    func show(on display: DisplayInfo) {
        guard let screen = display.screen else {
            hide()
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: true) }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        // Above the calibration window (which sits at .statusBar) so it can't hide a target dot.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: GridOverlayView(model: model))
        return panel
    }
}

private struct GridOverlayView: View {
    let model: GridOverlayModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.accentColor.opacity(0.10)
                TargetDot()
                    .position(x: model.point.x * geometry.size.width, y: model.point.y * geometry.size.height)
                // Keep the card out of the half of the screen the dot is in.
                VStack(spacing: 8) {
                    Text(model.title).font(.headline)
                    Text(model.detail).foregroundStyle(.secondary)
                    ProgressView(value: model.progress).frame(width: 220)
                    Text("Press Esc to cancel").font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .position(x: geometry.size.width / 2,
                          y: model.point.y < 0.5 ? geometry.size.height * 0.78 : geometry.size.height * 0.22)
            }
        }
        .ignoresSafeArea()
    }
}

private struct TargetDot: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.25)).frame(width: 64, height: 64)
            Circle().strokeBorder(Color.accentColor, lineWidth: 4).frame(width: 40, height: 40)
            Circle().fill(Color.white).frame(width: 12, height: 12)
        }
    }
}
