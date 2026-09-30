import Observation

@MainActor
@Observable
final class AppState {
    let tracker: HeadTracker
    let focus: FocusController
    let activity: ActivityMonitor

    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            focus.suspension = isPaused ? .userPaused : nil
            if isPaused {
                tracker.stop()
            } else {
                Task { [tracker] in await tracker.start() }
            }
        }
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
        Task { [tracker] in await tracker.start() }
    }
}
