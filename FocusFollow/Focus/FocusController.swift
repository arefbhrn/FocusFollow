import AppKit
import Observation
import OSLog

/// Turns head pose into focus changes: classify, wait out the dwell delay, then switch screens.
@MainActor
@Observable
final class FocusController {
    private static let logger = Logger(subsystem: "com.arefbhrn.focusfollow", category: "focus")
    private static let tickInterval = Duration.milliseconds(66)

    /// Set by `AppState`.
    var isPaused = false

    private(set) var layout: DisplayLayout
    private(set) var calibration: Calibration?
    private(set) var accessibilityTrusted: Bool
    /// Latest classification of the smoothed pose, before the dwell delay. `nil` without a face or calibration.
    private(set) var evaluation: ScreenClassifier.Evaluation?
    /// Classification that has been stable for the dwell delay.
    private(set) var confirmed: ScreenClassifier.Result?
    let session: CalibrationSession

    /// Extra condition for switching, e.g. typing and mouse activity in Phase 3. Return `false` to hold focus.
    @ObservationIgnored var switchingGate: @MainActor () -> Bool = { true }

    @ObservationIgnored private let tracker: HeadTracker
    @ObservationIgnored private let windows: WindowTracker
    @ObservationIgnored private var classifier: ScreenClassifier?
    @ObservationIgnored private var dwell = DwellFilter(delay: FocusSettings.dwellDelay)
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var lastTrustCheck = 0.0
    @ObservationIgnored private var lastWindowPoll = 0.0

    init(tracker: HeadTracker) {
        self.tracker = tracker
        let layout = DisplayLayout.current()
        self.layout = layout
        windows = WindowTracker(layout: layout)
        session = CalibrationSession(tracker: tracker)
        accessibilityTrusted = AccessibilityPermission.isTrusted

        loadCalibration()

        session.onFinish = { [weak self] calibration in
            self?.apply(calibration)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensChanged()
            }
        }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: Self.tickInterval)
            }
        }
    }

    var isCalibrated: Bool {
        classifier != nil
    }

    /// Shows the system prompt and opens the Accessibility pane.
    func requestAccessibility() {
        AccessibilityPermission.requestPrompt()
        AccessibilityPermission.openSettings()
    }

    /// Human-readable classification of the current pose, e.g. "Display 2 (LG)" or "Away".
    func label(for result: ScreenClassifier.Result) -> String {
        switch result {
        case .screen(let id): layout.label(for: id)
        case .away: "Away"
        }
    }

    // MARK: - Calibration

    private func loadCalibration() {
        calibration = CalibrationStore.load(arrangementKey: layout.key)
        rebuildClassifier()
    }

    private func apply(_ calibration: Calibration) {
        guard calibration.arrangementKey == layout.key else { return }
        CalibrationStore.save(calibration)
        self.calibration = calibration
        rebuildClassifier()
    }

    private func rebuildClassifier() {
        let stats = Dictionary(
            (calibration?.screens ?? []).map { ($0.id, $0.stats) },
            uniquingKeysWith: { _, latest in latest }
        )
        classifier = stats.isEmpty ? nil : ScreenClassifier(stats: stats)
        dwell.reset()
        evaluation = nil
        confirmed = nil
    }

    private func screensChanged() {
        let newLayout = DisplayLayout.current()
        guard newLayout != layout else { return }
        Self.logger.info("Display arrangement changed: \(newLayout.displays.count) displays")
        if session.isActive { session.cancel() }
        layout = newLayout
        windows.layout = newLayout
        loadCalibration()
    }

    // MARK: - Loop

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime

        // There is no notification for Accessibility changes, so poll.
        if now - lastTrustCheck >= 2 {
            lastTrustCheck = now
            let trusted = AccessibilityPermission.isTrusted
            if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        }
        if accessibilityTrusted, now - lastWindowPoll >= 0.25 {
            lastWindowPoll = now
            windows.poll()
        }

        guard !session.isActive, let classifier else {
            clearClassification()
            return
        }
        guard let pose = tracker.pose else {
            if evaluation != nil { evaluation = nil }
            _ = dwell.update(nil, at: now)
            return
        }

        let latest = classifier.evaluate(pose)
        evaluation = latest
        dwell.delay = FocusSettings.dwellDelay
        guard let newlyConfirmed = dwell.update(latest.result, at: now) else { return }
        confirmed = newlyConfirmed
        if case .screen(let id) = newlyConfirmed {
            switchIfNeeded(to: id)
        }
    }

    private func clearClassification() {
        if evaluation != nil { evaluation = nil }
        if confirmed != nil { confirmed = nil }
        dwell.reset()
    }

    private func switchIfNeeded(to id: String) {
        guard !isPaused, accessibilityTrusted, switchingGate(),
              let display = layout.display(withID: id) else { return }
        windows.poll()
        guard windows.focusedDisplayID != id else { return }
        Self.logger.info("Switching focus to \(id, privacy: .public)")
        windows.focus(on: display)
    }
}
