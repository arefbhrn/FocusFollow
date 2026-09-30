import SwiftUI

struct MenuContent: View {
    @Bindable var appState: AppState

    var body: some View {
        Text(statusText)

        if appState.tracker.status == .permissionDenied {
            Button("Allow Camera Access…") {
                CameraPermission.openSettings()
            }
        }

        Divider()

        Button(appState.isPaused ? "Resume" : "Pause") {
            appState.isPaused.toggle()
        }

        Divider()

        Button("Quit FocusFollow") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusText: String {
        if appState.isPaused { return "FocusFollow is paused" }
        switch appState.tracker.status {
        case .stopped, .requestingPermission: return "Starting…"
        case .permissionDenied: return "No camera permission"
        case .noCamera: return "No camera found"
        case .failed: return "Camera error"
        case .running: return appState.tracker.pose == nil ? "Active — no face" : "Active"
        }
    }
}
