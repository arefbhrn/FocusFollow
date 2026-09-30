import SwiftUI

@main
struct FocusFollowApp: App {
    /// SwiftUI may rebuild the App struct, so the state lives in a static to be created exactly once.
    private static let sharedState: AppState = {
        SingleInstance.exitIfAnotherInstanceIsRunning()
        return AppState()
    }()

    @State private var appState = FocusFollowApp.sharedState

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
