import SwiftUI

struct SettingsView: View {
    static let windowID = "settings"

    let tracker: HeadTracker
    let focus: FocusController
    @State private var loginItem = LaunchAtLogin()
    @Environment(\.openWindow) private var openWindow

    @AppStorage(FocusSettings.dwellDelayKey) private var dwellDelay = FocusSettings.defaultDwellDelay
    @AppStorage(FocusSettings.typingPauseKey) private var typingPause = FocusSettings.defaultTypingPause
    @AppStorage(FocusSettings.mousePauseKey) private var mousePause = FocusSettings.defaultMousePause
    @AppStorage(FocusSettings.awayThresholdKey) private var awayThreshold = FocusSettings.defaultAwayThreshold
    @AppStorage(FocusSettings.moveCursorKey) private var moveCursor = FocusSettings.defaultMoveCursor
    @AppStorage(FocusSettings.windowFocusKey) private var windowFocus = FocusSettings.defaultWindowFocus

    var body: some View {
        Form {
            Section("Switching") {
                SecondsSlider(
                    title: "Glance delay",
                    help: "How long you must look at a screen before focus follows. Longer ignores quick glances.",
                    value: $dwellDelay,
                    range: FocusSettings.dwellDelayRange,
                    step: 0.05
                )
                SecondsSlider(
                    title: "Pause after typing",
                    help: "Focus stays put for this long after your last keystroke. 0 turns it off.",
                    value: $typingPause,
                    range: FocusSettings.typingPauseRange,
                    step: 0.5
                )
                SecondsSlider(
                    title: "Pause after mouse use",
                    help: "Focus stays put for this long after you last moved the mouse or scrolled. 0 turns it off.",
                    value: $mousePause,
                    range: FocusSettings.mousePauseRange,
                    step: 0.5
                )
                Toggle("Move the cursor with focus", isOn: $moveCursor)
            }

            Section("Window focus (experimental)") {
                Toggle("Focus windows on the same screen", isOn: $windowFocus)
                Text("Looking at a window on the current screen focuses it. Needs a gaze grid (Calibrate → Calibrate Gaze Grid). Screens where the estimate is less accurate get a wider dead zone around window borders, and screens with an error above \(Int(FocusSettings.maximumWindowError * 100))% are skipped.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Head-turn tolerance") {
                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $awayThreshold, in: FocusSettings.awayThresholdRange) {
                        Text("Tolerance")
                    } minimumValueLabel: {
                        Text("Strict")
                    } maximumValueLabel: {
                        Text("Relaxed")
                    }
                    Text("How far off-center you can look and still count as facing a screen. Strict ignores more poses as looking away; relaxed switches more readily.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Reset to Default") { awayThreshold = FocusSettings.defaultAwayThreshold }
                    .disabled(awayThreshold == FocusSettings.defaultAwayThreshold)
            }

            Section("Camera") {
                CameraPicker(tracker: tracker)
            }

            Section("Calibration") {
                if focus.layout.displays.isEmpty {
                    Text("No displays found").foregroundStyle(.secondary)
                }
                ForEach(focus.layout.displays) { display in
                    LabeledContent(focus.layout.label(for: display.id)) {
                        VStack(alignment: .trailing, spacing: 2) {
                            if focus.isCalibrated(display.id) {
                                Label("Calibrated", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else {
                                Label("Not calibrated", systemImage: "exclamationmark.circle")
                                    .foregroundStyle(.orange)
                            }
                            gridStatus(for: display.id)
                        }
                    }
                }
                if focus.hasNewDisplaySetup {
                    Text("This display setup has not been calibrated yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Recalibrate…") {
                    openWindow(id: CalibrationView.windowID)
                    NSApp.activate()
                }
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(
                    get: { loginItem.isEnabled || loginItem.needsApproval },
                    set: { loginItem.setEnabled($0) }
                ))
                if loginItem.needsApproval {
                    HStack {
                        Text("Approve FocusFollow in System Settings to finish.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open Login Items…") { loginItem.openLoginItemsSettings() }
                    }
                }
                if let message = loginItem.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }
}

private struct SecondsSlider: View {
    let title: String
    let help: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                Text(value == 0 ? "Off" : "\(value, format: .number.precision(.fractionLength(1...2))) s")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: step)
                .labelsHidden()
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension SettingsView {
    @ViewBuilder
    func gridStatus(for displayID: String) -> some View {
        if let model = focus.gazeModels[displayID] {
            let usable = model.gateError <= FocusSettings.maximumWindowError
            Text("Gaze grid: error \(model.gateError, format: .percent.precision(.fractionLength(0)))\(usable ? "" : " (too coarse for windows)")")
                .font(.caption)
                .foregroundStyle(usable ? Color.secondary : Color.orange)
        } else if focus.isCalibrated(displayID) {
            Text("No gaze grid")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
