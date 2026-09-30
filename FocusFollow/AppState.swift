import Observation

@MainActor
@Observable
final class AppState {
    let tracker: HeadTracker
    let focus: FocusController

    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            focus.isPaused = isPaused
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
        focus = FocusController(tracker: tracker)
        Task { [tracker] in await tracker.start() }
    }
}
