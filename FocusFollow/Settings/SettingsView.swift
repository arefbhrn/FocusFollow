import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general, switching, windows, displays
}

struct SettingsView: View {
    static let windowID = "settings"

    let tracker: HeadTracker
    let focus: FocusController
    @State private var tab: SettingsTab

    init(tracker: HeadTracker, focus: FocusController, tab: SettingsTab = .general) {
        self.tracker = tracker
        self.focus = focus
        _tab = State(initialValue: tab)
    }

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab(tracker: tracker)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            SwitchingTab()
                .tabItem { Label("Switching", systemImage: "arrow.left.arrow.right") }
                .tag(SettingsTab.switching)
            WindowsTab(focus: focus)
                .tabItem { Label("Windows", systemImage: "macwindow") }
                .tag(SettingsTab.windows)
            DisplaysTab(focus: focus)
                .tabItem { Label("Displays", systemImage: "display") }
                .tag(SettingsTab.displays)
        }
        .frame(width: 520)
    }
}

// MARK: - General

private struct GeneralTab: View {
    let tracker: HeadTracker
    @State private var loginItem = LaunchAtLogin()

    var body: some View {
        Form {
            Section {
                CameraPicker(tracker: tracker)
            } header: {
                Text("Camera")
            } footer: {
                Text("FocusFollow only looks at where your head points. Frames stay in memory and are never saved or sent.")
            }

            Section("Startup") {
                Toggle("Open at login", isOn: Binding(
                    get: { loginItem.isEnabled || loginItem.needsApproval },
                    set: { loginItem.setEnabled($0) }
                ))
                if loginItem.needsApproval {
                    LabeledContent {
                        Button("Open Login Items…") { loginItem.openLoginItemsSettings() }
                    } label: {
                        Label("Approve FocusFollow in System Settings to finish.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                }
                if let message = loginItem.errorMessage {
                    Label(message, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section("Shortcuts") {
                LabeledContent("Pause or resume") {
                    Text(HotKeyConfig.displayString)
                        .font(.system(.body, design: .rounded))
                        .padding(.horizontal, Theme.Space.s)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: Theme.Radius.s))
                }
            }

            Section {
                HStack {
                    Spacer()
                    Text("FocusFollow \(Bundle.main.versionString)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }
}

// MARK: - Switching

private struct SwitchingTab: View {
    @AppStorage(FocusSettings.dwellDelayKey) private var dwellDelay = FocusSettings.defaultDwellDelay
    @AppStorage(FocusSettings.typingPauseKey) private var typingPause = FocusSettings.defaultTypingPause
    @AppStorage(FocusSettings.mousePauseKey) private var mousePause = FocusSettings.defaultMousePause
    @AppStorage(FocusSettings.awayThresholdKey) private var awayThreshold = FocusSettings.defaultAwayThreshold
    @AppStorage(FocusSettings.moveCursorKey) private var moveCursor = FocusSettings.defaultMoveCursor

    var body: some View {
        Form {
            Section("Timing") {
                SettingSlider(
                    title: "Glance delay",
                    help: "How long you look at a screen before focus follows. Longer ignores quick glances.",
                    value: $dwellDelay,
                    range: FocusSettings.dwellDelayRange,
                    step: 0.05,
                    format: .seconds
                )
                SettingSlider(
                    title: "Pause after typing",
                    help: "Focus stays put this long after your last keystroke.",
                    value: $typingPause,
                    range: FocusSettings.typingPauseRange,
                    step: 0.5,
                    format: .secondsOrOff
                )
                SettingSlider(
                    title: "Pause after mouse use",
                    help: "Focus stays put this long after you last moved the mouse or scrolled.",
                    value: $mousePause,
                    range: FocusSettings.mousePauseRange,
                    step: 0.5,
                    format: .secondsOrOff
                )
            }

            Section {
                SettingSlider(
                    title: "Head-turn tolerance",
                    help: "How far off-center you can look and still count as facing a screen. Strict treats more poses as looking away; relaxed switches more readily.",
                    value: $awayThreshold,
                    range: FocusSettings.awayThresholdRange,
                    step: 0.1,
                    format: .scale(low: "Strict", high: "Relaxed")
                )
                if awayThreshold != FocusSettings.defaultAwayThreshold {
                    Button("Reset to Default") { awayThreshold = FocusSettings.defaultAwayThreshold }
                        .buttonStyle(.link)
                }
            } header: {
                Text("Sensitivity")
            }

            Section("Behavior") {
                Toggle("Move the cursor with focus", isOn: $moveCursor)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Windows

private struct WindowsTab: View {
    let focus: FocusController
    @Environment(\.openWindow) private var openWindow
    @AppStorage(FocusSettings.windowFocusKey) private var windowFocus = FocusSettings.defaultWindowFocus

    var body: some View {
        Form {
            Section {
                Toggle("Focus windows on the same screen", isOn: $windowFocus)
            } header: {
                Text("Same-screen focus")
            } footer: {
                Text("Experimental. Looking at a window on the screen you're already on focuses it. It relies on head direction, so it works best with large windows that don't overlap.")
            }

            Section {
                if focus.layout.displays.isEmpty {
                    Text("No displays found").foregroundStyle(.secondary)
                }
                ForEach(focus.layout.displays) { display in
                    LabeledContent(focus.layout.label(for: display.id)) {
                        GazeGridBadge(focus: focus, displayID: display.id)
                    }
                }
                Button("Calibrate Gaze Grid…") {
                    openWindow(id: CalibrationView.windowID)
                    NSApp.activate()
                }
            } header: {
                Text("Accuracy per screen")
            } footer: {
                Text("Screens above \(Int(FocusSettings.maximumWindowError * 100))% error are skipped. On the others, the less accurate the estimate, the wider the no-switch zone around window borders.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Displays

private struct DisplaysTab: View {
    let focus: FocusController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section {
                if focus.layout.displays.isEmpty {
                    Text("No displays found").foregroundStyle(.secondary)
                }
                ForEach(focus.layout.displays) { display in
                    LabeledContent(focus.layout.label(for: display.id)) {
                        ScreenCalibrationBadge(calibrated: focus.isCalibrated(display.id))
                    }
                }
                Button("Recalibrate…") {
                    openWindow(id: CalibrationView.windowID)
                    NSApp.activate()
                }
            } header: {
                Text("Calibration")
            } footer: {
                Text(focus.hasNewDisplaySetup
                     ? "This display setup has not been calibrated yet."
                     : "Calibration is saved for each arrangement of displays, so it comes back when you reconnect the same ones.")
            }

        }
        .formStyle(.grouped)
    }
}

// MARK: - Shared pieces

private struct ScreenCalibrationBadge: View {
    let calibrated: Bool

    var body: some View {
        Label(calibrated ? "Calibrated" : "Not calibrated", systemImage: (calibrated ? Theme.Status.ok : .warning).symbol)
            .foregroundStyle(calibrated ? Theme.Status.ok.color : Theme.Status.warning.color)
    }
}

/// Status of a screen's gaze grid: none, usable, or too coarse for window focus.
private struct GazeGridBadge: View {
    let focus: FocusController
    let displayID: String

    var body: some View {
        if let model = focus.gazeModels[displayID] {
            let usable = model.gateError <= FocusSettings.maximumWindowError
            let kind: Theme.Status = usable ? (model.gateError <= 0.15 ? .ok : .warning) : .problem
            Label {
                Text("\(model.gateError, format: .percent.precision(.fractionLength(0))) error\(usable ? "" : " · too coarse")")
            } icon: {
                Image(systemName: kind.symbol)
            }
            .foregroundStyle(kind.color)
        } else {
            Label(focus.isCalibrated(displayID) ? "No gaze grid" : "Calibrate the screen first", systemImage: Theme.Status.neutral.symbol)
                .foregroundStyle(.secondary)
        }
    }
}

/// A labelled slider with a live value, no tick marks, and help text underneath.
private struct SettingSlider: View {
    enum Format {
        case seconds
        case secondsOrOff
        case scale(low: String, high: String)
    }

    let title: String
    let help: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: Format

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                Text(title)
                Spacer()
                if let text = valueText {
                    Text(text)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: Theme.Space.s) {
                if case .scale(let low, _) = format { Text(low).font(.caption).foregroundStyle(.secondary) }
                // Snap to the step in the binding so the slider shows no tick marks.
                Slider(value: Binding(
                    get: { value },
                    set: { value = (($0 - range.lowerBound) / step).rounded() * step + range.lowerBound }
                ), in: range) {
                    Text(title)
                }
                .labelsHidden()
                .accessibilityValue(accessibilityValue)
                if case .scale(_, let high) = format { Text(high).font(.caption).foregroundStyle(.secondary) }
            }
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.Space.xs)
    }

    private var valueText: String? {
        switch format {
        case .seconds: String(format: "%.2f s", value)
        case .secondsOrOff: value == 0 ? "Off" : String(format: "%.1f s", value)
        case .scale: nil
        }
    }

    private var accessibilityValue: String {
        switch format {
        case .seconds, .secondsOrOff: value == 0 ? "Off" : String(format: "%.2f seconds", value)
        case .scale(let low, let high): "\(Int(((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * 100)) percent between \(low) and \(high)"
        }
    }
}

private extension Bundle {
    var versionString: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }
}
