import SwiftUI

@main
struct FocusFollowApp: App {
    /// SwiftUI may rebuild the App struct, so the state lives in a static to be created exactly once.
    private static let sharedState: AppState = {
        SingleInstance.exitIfAnotherInstanceIsRunning()
        let state = AppState()
        #if DEBUG
        if let directory = UISnapshot.requestedDirectory {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { UISnapshot.run(appState: state, into: directory) }
        }
        #endif
        return state
    }()

    @State private var appState = FocusFollowApp.sharedState

    var body: some Scene {
        MenuBarExtra("FocusFollow", systemImage: appState.menuBarState.symbolName) {
            MenuContent(appState: appState)
        }
        .menuBarExtraStyle(.window)

        Window("FocusFollow Diagnostics", id: DebugView.windowID) {
            DebugView(tracker: appState.tracker, focus: appState.focus)
        }
        .windowResizability(.contentSize)

        Window("FocusFollow Settings", id: SettingsView.windowID) {
            SettingsView(tracker: appState.tracker, focus: appState.focus)
        }
        .windowResizability(.contentSize)

        Window("Calibrate FocusFollow", id: CalibrationView.windowID) {
            CalibrationView(focus: appState.focus, tracker: appState.tracker)
        }
        .windowResizability(.contentSize)
    }
}
