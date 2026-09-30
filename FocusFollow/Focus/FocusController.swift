import AppKit
import Observation
import OSLog

/// Turns head pose into focus changes: classify, wait out the dwell delay, then switch screens.
@MainActor
@Observable
final class FocusController {
    private static let logger = Logger(subsystem: "com.arefbhrn.focusfollow", category: "focus")
    private static let tickInterval = Duration.milliseconds(66)

    /// Set by `AppState` while the user paused or the system is asleep / locked. Holds all switching.
    var suspension: HoldReason?

    private(set) var layout: DisplayLayout
    private(set) var calibration: Calibration?
    private(set) var accessibilityTrusted: Bool
    /// Latest classification of the smoothed pose, before the dwell delay. `nil` without a face or calibration.
    private(set) var evaluation: ScreenClassifier.Evaluation? {
        didSet {
            if evaluation?.result != currentResult { currentResult = evaluation?.result }
        }
    }
    /// Just the classification in `evaluation`. Unlike `evaluation` it only changes when the result does,
    /// so views that show it (the menu) don't re-render every frame.
    private(set) var currentResult: ScreenClassifier.Result?
    /// Classification that has been stable for the dwell delay.
    private(set) var confirmed: ScreenClassifier.Result?
    /// The display setup changed to one with no saved calibration. Cleared once it is calibrated.
    private(set) var hasNewDisplaySetup = false
    let session: CalibrationSession
    let gridSession: GridCalibrationSession
    /// A screen recalibration replaced a calibration that had gaze grids. Cleared once a grid is saved again.
    private(set) var gridWasCleared = false
    /// Where on the classified screen the head points right now. Changes every frame; only debug views read it.
    private(set) var gaze: GazeEstimate?
    /// Gaze models by display ID and input set, for screens that have grid calibration.
    /// A set is missing when its fit failed, for example eye data was not captured.
    private(set) var gazeModels: [String: [GazeFeatureSet: GazeModel]] = [:]

    /// Why switching is held right now, or `nil` when free to switch. Updated every tick.
    private(set) var holdReason: HoldReason?

    /// Extra condition for switching, e.g. recent typing or mouse activity. Return a reason to hold focus.
    @ObservationIgnored var holdReasonProvider: @MainActor () -> HoldReason? = { nil }

    @ObservationIgnored private let tracker: HeadTracker
    @ObservationIgnored private let windows: WindowTracker
    @ObservationIgnored private var classifier: ScreenClassifier?
    @ObservationIgnored private var dwell = DwellFilter(delay: FocusSettings.dwellDelay)
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    /// Screen confirmed by the dwell filter whose switch was held back; retried while the user keeps looking at it.
    @ObservationIgnored private var pendingSwitch: String?
    @ObservationIgnored var onAccessibilityTrustChange: @MainActor (Bool) -> Void = { _ in }
    @ObservationIgnored private var lastTrustCheck = 0.0
    @ObservationIgnored private var lastWindowPoll = 0.0

    init(tracker: HeadTracker, activity: ActivityMonitor) {
        self.tracker = tracker
        let layout = DisplayLayout.current()
        self.layout = layout
        let windows = WindowTracker(layout: layout)
        windows.onWillWarpCursor = { [activity] in activity.noteCursorWarp() }
        self.windows = windows
        session = CalibrationSession(tracker: tracker)
        gridSession = GridCalibrationSession(tracker: tracker)
        accessibilityTrusted = AccessibilityPermission.isTrusted

        loadCalibration()

        session.onFinish = { [weak self] calibration in
            self?.apply(calibration)
        }
        gridSession.onFinish = { [weak self] results in
            self?.applyGrid(results)
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

    /// Whether the current display setup has a saved calibration for this display.
    func isCalibrated(_ displayID: String) -> Bool {
        calibration?.screens.contains { $0.id == displayID } ?? false
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
        if self.calibration?.screens.contains(where: { $0.grid != nil }) == true { gridWasCleared = true }
        CalibrationStore.save(calibration)
        self.calibration = calibration
        hasNewDisplaySetup = false
        rebuildClassifier()
    }

    /// Runs grid calibration on every screen that already has a screen calibration.
    func startGridCalibration() {
        let calibrated = layout.displays.filter { isCalibrated($0.id) }
        gridSession.start(displays: calibrated, layout: layout)
    }

    private func applyGrid(_ results: [String: [GridSample]]) {
        guard var calibration else { return }
        for index in calibration.screens.indices {
            if let grid = results[calibration.screens[index].id] {
                calibration.screens[index].grid = grid
            }
        }
        CalibrationStore.save(calibration)
        self.calibration = calibration
        gridWasCleared = false
        rebuildGazeModels()
    }

    private func rebuildGazeModels() {
        var models: [String: [GazeFeatureSet: GazeModel]] = [:]
        for screen in calibration?.screens ?? [] {
            guard let grid = screen.grid else { continue }
            for set in GazeFeatureSet.allCases {
                if let model = GazeModel.fit(grid, featureSet: set) {
                    models[screen.id, default: [:]][set] = model
                }
            }
        }
        gazeModels = models
        gaze = nil
    }

    private func rebuildClassifier() {
        rebuildGazeModels()
        let stats = Dictionary(
            (calibration?.screens ?? []).map { ($0.id, $0.stats) },
            uniquingKeysWith: { _, latest in latest }
        )
        classifier = stats.isEmpty ? nil : ScreenClassifier(stats: stats)
        dwell.reset()
        evaluation = nil
        confirmed = nil
        pendingSwitch = nil
    }

    private func screensChanged() {
        let newLayout = DisplayLayout.current()
        guard newLayout != layout else { return }
        Self.logger.info("Display arrangement changed: \(newLayout.displays.count) displays")
        if session.isActive { session.cancel() }
        if gridSession.phase != .idle { gridSession.cancel() }
        layout = newLayout
        windows.layout = newLayout
        loadCalibration()
        hasNewDisplaySetup = calibration == nil
    }

    // MARK: - Loop

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime

        // There is no notification for Accessibility changes, so poll.
        if now - lastTrustCheck >= 2 {
            lastTrustCheck = now
            let trusted = AccessibilityPermission.isTrusted
            if trusted != accessibilityTrusted {
                accessibilityTrusted = trusted
                onAccessibilityTrustChange(trusted)
            }
        }
        if accessibilityTrusted, now - lastWindowPoll >= 0.25 {
            lastWindowPoll = now
            windows.poll()
        }

        let hold = suspension ?? holdReasonProvider()
        if hold != holdReason { holdReason = hold }

        classifier?.awayThreshold = FocusSettings.awayThreshold
        guard !session.isActive, !gridSession.isActive, let classifier else {
            clearClassification()
            return
        }
        guard let pose = tracker.pose else {
            if evaluation != nil { evaluation = nil }
            if gaze != nil { gaze = nil }
            _ = dwell.update(nil, at: now)
            return
        }

        let latest = classifier.evaluate(pose)
        evaluation = latest
        updateGaze(for: latest.result, pose: pose)
        dwell.delay = FocusSettings.dwellDelay
        if let newlyConfirmed = dwell.update(latest.result, at: now) {
            confirmed = newlyConfirmed
            // Only a screen triggers a switch; `.away` (phone, ceiling, desk) never does.
            if case .screen(let id) = newlyConfirmed {
                pendingSwitch = id
            } else {
                pendingSwitch = nil
            }
        }

        guard let id = pendingSwitch else { return }
        guard latest.result == .screen(id) else {
            pendingSwitch = nil
            return
        }
        guard holdReason == nil else { return }
        pendingSwitch = nil
        switchIfNeeded(to: id)
    }

    private func updateGaze(for result: ScreenClassifier.Result, pose: HeadPose) {
        if case .screen(let id) = result, let models = gazeModels[id] {
            let input = GazeInput(pose: pose, eye: tracker.eyes)
            // Use the preferred model, falling back when it has no fit or no eyes in this frame.
            let order: [GazeFeatureSet] = FocusSettings.useEyes ? [.headEyes, .head, .headCross] : [.head, .headCross]
            let estimate = order.lazy.compactMap { set in
                models[set]?.predict(input).map { GazeEstimate(displayID: id, x: $0.x, y: $0.y, featureSet: set) }
            }.first
            if let estimate {
                gaze = estimate
            } else if gaze != nil {
                gaze = nil
            }
        } else if gaze != nil {
            gaze = nil
        }
    }

    private func clearClassification() {
        if gaze != nil { gaze = nil }
        if evaluation != nil { evaluation = nil }
        if confirmed != nil { confirmed = nil }
        pendingSwitch = nil
        dwell.reset()
    }

    private func switchIfNeeded(to id: String) {
        guard accessibilityTrusted,
              let display = layout.display(withID: id) else { return }
        windows.poll()
        guard windows.focusedDisplayID != id else { return }
        Self.logger.info("Switching focus to \(id, privacy: .public)")
        windows.focus(on: display)
    }
}
