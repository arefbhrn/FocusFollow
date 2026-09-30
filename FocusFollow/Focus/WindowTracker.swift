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
    /// Process and frame of the frontmost app's focused window, as of the last `poll()`.
    private(set) var focusedPID: pid_t?
    private(set) var focusedFrame: CGRect?
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
              !AX.isMinimized(window),
              let frame = AX.frame(of: window),
              let display = layout.display(containing: CGPoint(x: frame.midX, y: frame.midY)) else {
            focusedDisplayID = nil
            focusedPID = nil
            focusedFrame = nil
            return
        }
        focusedDisplayID = display.id
        focusedPID = app.processIdentifier
        focusedFrame = frame
        remembered[display.id] = Remembered(pid: app.processIdentifier, window: window)
    }

    /// Focuses the last window used on `display`, or the frontmost one there, and moves the cursor to it if that setting is on.
    func focus(on display: DisplayInfo) {
        if let entry = remembered[display.id] {
            if focus(entry, on: display) { return }
            remembered[display.id] = nil
        }
        if let entry = frontmostWindow(on: display), focus(entry, on: display) {
            remembered[display.id] = entry
            return
        }
        // Nothing visible to focus: at most move the cursor (when enabled), never activate or raise anything.
        Self.logger.info("No window to focus on \(display.id, privacy: .public)")
        warpCursor(to: CGPoint(x: display.bounds.midX, y: display.bounds.midY))
    }

    /// Visible normal windows that touch `display`, front to back. Windows that hide others but must not be
    /// picked (our own, or ones centered on another display) are included and marked not selectable.
    func candidates(on display: DisplayInfo) -> [WindowCandidate] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsInfo = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.width >= 50, bounds.height >= 50,
                  bounds.intersects(display.bounds) else { return nil }
            let selectable = pid != ownPID && display.bounds.contains(CGPoint(x: bounds.midX, y: bounds.midY))
            return WindowCandidate(number: number, pid: pid, bounds: bounds, selectable: selectable)
        }
    }

    /// Whether `candidate` is already the focused window, as of the last `poll()`.
    func isFocused(_ candidate: WindowCandidate) -> Bool {
        guard focusedPID == candidate.pid, let frame = focusedFrame else { return false }
        return Self.sameFrame(frame, candidate.bounds)
    }

    /// Focuses `candidate` and moves the cursor to it if that setting is on. `false` if no matching window was found.
    @discardableResult
    func focus(_ candidate: WindowCandidate, on display: DisplayInfo) -> Bool {
        guard let window = axWindow(pid: candidate.pid, matching: candidate.bounds) else { return false }
        let entry = Remembered(pid: candidate.pid, window: window)
        guard focus(entry, on: display) else { return false }
        remembered[display.id] = entry
        return true
    }

    private func axWindow(pid: pid_t, matching bounds: CGRect) -> AXUIElement? {
        AX.windows(pid: pid).first { window in
            guard !AX.isMinimized(window), let frame = AX.frame(of: window) else { return false }
            return Self.sameFrame(frame, bounds)
        }
    }

    private static func sameFrame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 3 && abs(a.minY - b.minY) < 3 && abs(a.width - b.width) < 3 && abs(a.height - b.height) < 3
    }

    private func focus(_ entry: Remembered, on display: DisplayInfo) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: entry.pid),
              !app.isHidden,
              !AX.isMinimized(entry.window),
              let frame = AX.frame(of: entry.window),
              display.bounds.contains(CGPoint(x: frame.midX, y: frame.midY)),
              isOnScreen(pid: entry.pid, frame: frame) else { return false }
        AX.focus(window: entry.window, pid: entry.pid)
        warpCursor(to: CGPoint(x: frame.midX, y: frame.midY))
        focusedDisplayID = display.id
        // Don't wait for the next poll, or callers keep seeing the old window as focused.
        focusedPID = entry.pid
        focusedFrame = frame
        return true
    }

    /// Whether a normal window of `pid` with this frame is currently visible. Excludes minimized, hidden-app and other-Space windows.
    private func isOnScreen(pid: pid_t, frame: CGRect) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return list.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let boundsInfo = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary) else { return false }
            return abs(frame.minX - bounds.minX) < 3
                && abs(frame.minY - bounds.minY) < 3
                && abs(frame.width - bounds.width) < 3
                && abs(frame.height - bounds.height) < 3
        }
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

        guard let window = axWindow(pid: target.pid, matching: target.bounds) else { return nil }
        return Remembered(pid: target.pid, window: window)
    }

    private func warpCursor(to point: CGPoint) {
        guard FocusSettings.moveCursor else { return }
        onWillWarpCursor()
        CGWarpMouseCursorPosition(point)
    }
}
