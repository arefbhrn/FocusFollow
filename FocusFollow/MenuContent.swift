import SwiftUI

struct MenuContent: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(statusText)

        if let lookingAt = lookingAtText {
            Text(lookingAt)
        }

        Text(calibrationText)

        if !appState.focus.accessibilityTrusted {
            Text("Accessibility access needed")
            Button("Grant Accessibility Access…") {
                appState.focus.requestAccessibility()
            }
        }

        if appState.tracker.status == .permissionDenied {
            Button("Allow Camera Access…") {
                CameraPermission.openSettings()
            }
        }

        Divider()

        Button(appState.isPaused ? "Resume" : "Pause") {
            appState.isPaused.toggle()
        }

        Button("Show Debug Window") {
            openWindow(id: DebugView.windowID)
            NSApp.activate()
        }

        Divider()

        Button("Quit FocusFollow") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var lookingAtText: String? {
        guard let result = appState.focus.evaluation?.result else { return nil }
        return "Looking at: \(appState.focus.label(for: result))"
    }

    private var calibrationText: String {
        guard let calibration = appState.focus.calibration else { return "Not calibrated for this display setup" }
        let count = calibration.screens.count
        return "Calibrated: \(count) of \(appState.focus.layout.displays.count) displays"
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
