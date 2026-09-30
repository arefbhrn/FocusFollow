import SwiftUI

/// The popover under the menu bar icon: what FocusFollow is doing, what needs attention, and quick actions.
struct MenuContent: View {
    @Bindable var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            header
            statusCard
            pauseButton
            Divider()
            actions
        }
        .padding(Theme.Space.l)
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Space.m) {
            IconBadge(symbol: appState.menuBarState.symbolName, tint: appState.menuBarState.tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText).font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if appState.isUserPaused { return "Paused" }
        if appState.isSystemSuspended { return appState.focus.suspension?.label ?? "Suspended" }
        switch appState.tracker.status {
        case .stopped, .requestingPermission: return "Starting…"
        case .permissionDenied: return "Camera access needed"
        case .noCamera: return "No camera found"
        case .failed: return "Camera error"
        case .running: return appState.tracker.hasFace ? "Active" : "No face in view"
        }
    }

    private var subtitle: String? {
        if appState.isUserPaused { return "Focus stays where you put it." }
        if appState.isSystemSuspended { return nil }
        // Pause and suspension are already in the title; only input holds are extra information.
        if let hold = appState.focus.holdReason { return hold.label }
        if let result = appState.focus.currentResult { return "Looking at \(appState.focus.label(for: result))" }
        return nil
    }

    // MARK: - Status

    private var statusCard: some View {
        Card(padding: Theme.Space.m) {
            VStack(spacing: Theme.Space.s) {
                StatusRow(
                    symbol: "camera",
                    title: "Camera",
                    status: cameraStatus.kind,
                    detail: cameraStatus.text,
                    fixTitle: "Allow…",
                    fix: { CameraPermission.openSettings() }
                )
                Divider()
                StatusRow(
                    symbol: "hand.raised",
                    title: "Accessibility",
                    status: appState.focus.accessibilityTrusted ? .ok : .warning,
                    detail: appState.focus.accessibilityTrusted ? "Allowed" : "Needed",
                    fixTitle: "Allow…",
                    fix: { appState.focus.requestAccessibility() }
                )
                Divider()
                StatusRow(
                    symbol: "display",
                    title: "Displays",
                    status: calibrationStatus.kind,
                    detail: calibrationStatus.text,
                    fixTitle: "Calibrate…",
                    fix: { open(CalibrationView.windowID) }
                )
            }
        }
    }

    private var cameraStatus: (kind: Theme.Status, text: String) {
        switch appState.tracker.status {
        case .running: (.ok, "Running")
        case .requestingPermission: (.neutral, "Starting…")
        case .stopped: (.neutral, "Off")
        case .permissionDenied: (.problem, "Access denied")
        case .noCamera: (.problem, "Not found")
        case .failed: (.problem, "Error")
        }
    }

    private var calibrationStatus: (kind: Theme.Status, text: String) {
        let total = appState.focus.layout.displays.count
        if appState.focus.hasNewDisplaySetup { return (.warning, "New setup") }
        guard let calibration = appState.focus.calibration else { return (.warning, "Not calibrated") }
        let done = calibration.screens.count
        return (done == total ? .ok : .warning, done == total ? "\(done) calibrated" : "\(done) of \(total)")
    }

    // MARK: - Actions

    private var pauseButton: some View {
        VStack(spacing: Theme.Space.xs) {
            pauseControl
            Text("Pause or resume from anywhere with \(HotKeyConfig.displayString)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var pauseControl: some View {
        Button {
            appState.isUserPaused.toggle()
        } label: {
            Label(appState.isUserPaused ? "Resume" : "Pause", systemImage: appState.isUserPaused ? "play.fill" : "pause.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        // Shown for reference; the actual shortcut is the global hotkey, which also works while the popover is closed.
        .keyboardShortcut(HotKeyConfig.keyEquivalent, modifiers: HotKeyConfig.eventModifiers)
        .help("\(appState.isUserPaused ? "Resume" : "Pause") (\(HotKeyConfig.displayString))")
    }

    private var actions: some View {
        VStack(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                ActionTile(symbol: "viewfinder", title: "Calibrate") { open(CalibrationView.windowID) }
                ActionTile(symbol: "gearshape", title: "Settings") { open(SettingsView.windowID) }
                ActionTile(symbol: "waveform.path.ecg", title: "Diagnostics") { open(DebugView.windowID) }
            }
            HStack {
                Spacer()
                Button("Quit FocusFollow") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut("q")
            }
        }
    }

    private func open(_ id: String) {
        openWindow(id: id)
        NSApp.activate()
    }
}
