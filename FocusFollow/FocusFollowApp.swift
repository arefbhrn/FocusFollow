import SwiftUI

@main
struct FocusFollowApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("FocusFollow", systemImage: appState.isPaused ? "eye.slash" : "eye") {
            MenuContent(appState: appState)
        }
    }
}
