import Observation

@MainActor
@Observable
final class AppState {
    var isPaused = false
}
