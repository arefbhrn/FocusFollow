import Observation

@MainActor
@Observable
final class AppState {
    let tracker = HeadTracker()

    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            if isPaused {
                tracker.stop()
            } else {
                Task { [tracker] in await tracker.start() }
            }
        }
    }

    init() {
        Task { [tracker] in await tracker.start() }
    }
}
