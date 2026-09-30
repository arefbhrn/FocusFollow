import SwiftUI

@main
struct FocusFollowApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("FocusFollow", systemImage: appState.menuBarState.symbolName) {
            MenuContent(appState: appState)
        }

        Window("FocusFollow Debug", id: DebugView.windowID) {
            DebugView(tracker: appState.tracker, focus: appState.focus)
        }
        .windowResizability(.contentSize)

        Window("Calibrate FocusFollow", id: CalibrationView.windowID) {
            CalibrationView(focus: appState.focus, tracker: appState.tracker)
        }
        .windowResizability(.contentSize)
    }
}
