import AppKit
import CoreGraphics
import OSLog

/// Remembers the last focused window on each display and moves focus to one on demand.
@MainActor
final class WindowTracker {
    private struct Remembered {
        var pid: pid_t
        var window: AXUIElement
    }

    private static let logger = Logger(subsystem: "com.arefbhrn.focusfollow", category: "windows")

    var layout: DisplayLayout
    /// Display of the frontmost app's focused window, as of the last `poll()`. `nil` if unknown or it's our own window.
    private(set) var focusedDisplayID: String?
    /// Called right before the cursor is warped, so input monitors can ignore our own movement.
    var onWillWarpCursor: @MainActor () -> Void = {}

    private var remembered: [String: Remembered] = [:]
    private var observer: NSObjectProtocol?
    private let ownPID = ProcessInfo.processInfo.processIdentifier

    init(layout: DisplayLayout) {
        self.layout = layout
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
    }

    /// Reads the frontmost app's focused window and remembers it for its display.
    func poll() {
        guard AccessibilityPermission.isTrusted,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ownPID,
              let window = AX.focusedWindow(pid: app.processIdentifier),
              let frame = AX.frame(of: window),
              let display = layout.display(containing: CGPoint(x: frame.midX, y: frame.midY)) else {
            focusedDisplayID = nil
            return
        }
        focusedDisplayID = display.id
        remembered[display.id] = Remembered(pid: app.processIdentifier, window: window)
    }

    /// Focuses the last window used on `display`, or the frontmost one there, and moves the cursor to it.
    func focus(on display: DisplayInfo) {
        if let entry = remembered[display.id] {
            if focus(entry, on: display) { return }
            remembered[display.id] = nil
        }
        if let entry = frontmostWindow(on: display), focus(entry, on: display) {
            remembered[display.id] = entry
            return
        }
        Self.logger.info("No window to focus on \(display.id, privacy: .public)")
        warpCursor(to: CGPoint(x: display.bounds.midX, y: display.bounds.midY))
    }

    private func focus(_ entry: Remembered, on display: DisplayInfo) -> Bool {
        guard NSRunningApplication(processIdentifier: entry.pid) != nil,
              let frame = AX.frame(of: entry.window),
              display.bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return false }
        AX.focus(window: entry.window, pid: entry.pid)
        warpCursor(to: CGPoint(x: frame.midX, y: frame.midY))
        focusedDisplayID = display.id
        return true
    }

    /// Topmost normal window on the display, found through the window server and matched to an AX element.
    private func frontmostWindow(on display: DisplayInfo) -> Remembered? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        // The list is ordered front to back.
        var fallback: (pid: pid_t, bounds: CGRect)?
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsInfo = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.width >= 50, bounds.height >= 50,
                  bounds.intersects(display.bounds) else { continue }
            if display.bounds.contains(CGPoint(x: bounds.midX, y: bounds.midY)) {
                fallback = (pid, bounds)
                break
            }
            if fallback == nil { fallback = (pid, bounds) }
        }
        guard let target = fallback else { return nil }

        let windows = AX.windows(pid: target.pid)
        let match = windows.first { window in
            guard let frame = AX.frame(of: window) else { return false }
            return abs(frame.minX - target.bounds.minX) < 3
                && abs(frame.minY - target.bounds.minY) < 3
                && abs(frame.width - target.bounds.width) < 3
                && abs(frame.height - target.bounds.height) < 3
        }
        guard let window = match else { return nil }
        return Remembered(pid: target.pid, window: window)
    }

    private func warpCursor(to point: CGPoint) {
        onWillWarpCursor()
        CGWarpMouseCursorPosition(point)
    }
}
