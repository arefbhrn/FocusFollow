import SwiftUI

struct MenuContent: View {
    @Bindable var appState: AppState

    var body: some View {
        Text(appState.isPaused ? "FocusFollow is paused" : "FocusFollow is active")

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
}
