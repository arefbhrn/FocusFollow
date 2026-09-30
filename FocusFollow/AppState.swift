import Observation

@MainActor
@Observable
final class AppState {
    let tracker: HeadTracker
    let focus: FocusController
    let activity: ActivityMonitor

    /// The user turned FocusFollow off. Independent of system suspension, so neither overrides the other.
    var isUserPaused = false {
        didSet {
            guard isUserPaused != oldValue else { return }
            updateRunState()
        }
    }

    /// Sleep, lock or screen saver are active. Cleared automatically when they end.
    private(set) var systemSuspensions: Set<SystemSuspension> = [] {
        didSet {
            guard systemSuspensions != oldValue else { return }
            updateRunState()
        }
    }

    @ObservationIgnored private let systemState: SystemStateMonitor
    @ObservationIgnored private var pauseHotKey: GlobalHotKey?

    var isSystemSuspended: Bool {
        !systemSuspensions.isEmpty
    }

    /// The camera runs and switching is allowed only when neither the user nor the system says stop.
    var isRunning: Bool {
        !isUserPaused && !isSystemSuspended
    }

    init() {
        let tracker = HeadTracker()
        self.tracker = tracker
        let activity = ActivityMonitor()
        self.activity = activity
        let focus = FocusController(tracker: tracker, activity: activity)
        focus.holdReasonProvider = { [activity] in activity.holdReason() }
        focus.onAccessibilityTrustChange = { [activity] trusted in activity.accessibilityTrustChanged(trusted) }
        self.focus = focus
        let systemState = SystemStateMonitor()
        self.systemState = systemState

        systemState.onChange = { [weak self] active in
            self?.systemSuspensions = active
        }
        pauseHotKey = GlobalHotKey(keyCode: HotKeyConfig.keyCode, modifiers: HotKeyConfig.modifiers) { [weak self] in
            self?.isUserPaused.toggle()
        }
        Task { [tracker] in await tracker.start() }
    }

    /// The suspension to show when several apply: a user pause first, then the first system reason in declaration order.
    private var suspensionReason: HoldReason? {
        if isUserPaused { return .userPaused }
        let first = SystemSuspension.allCases.first { systemSuspensions.contains($0) }
        return first.map { .suspended($0) }
    }

    private func updateRunState() {
        focus.suspension = suspensionReason
        if isRunning {
            // Re-check when the task runs: a suspend may have arrived in between.
            Task { [weak self] in
                guard let self, self.isRunning else { return }
                await self.tracker.start()
            }
        } else {
            tracker.stop()
        }
    }
}
