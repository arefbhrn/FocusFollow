import AppKit
import OSLog

/// Tracks when the user last typed or used the mouse, so focus doesn't jump mid-action.
/// Only timestamps are kept, never key contents.
@MainActor
final class ActivityMonitor {
    private static let logger = Logger(subsystem: "com.arefbhrn.focusfollow", category: "activity")
    /// Mouse-moved events this soon after our own cursor warp are not user activity.
    private static let warpIgnoreWindow: TimeInterval = 0.3

    private static let typingEvents: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
    private static let mouseEvents: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .scrollWheel, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
    ]

    private var lastTyping = -TimeInterval.infinity
    private var lastMouse = -TimeInterval.infinity
    private var ignoreMouseMovesUntil = -TimeInterval.infinity
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init() {
        installLocalMonitor()
        installGlobalMonitor()
    }

    /// Call right before warping the cursor ourselves.
    func noteCursorWarp() {
        ignoreMouseMovesUntil = Self.now() + Self.warpIgnoreWindow
    }

    /// Why switching should be held right now, or `nil` when there has been no recent input.
    func holdReason() -> HoldReason? {
        let now = Self.now()
        if now - lastTyping < FocusSettings.typingPause { return .typing }
        if now - lastMouse < FocusSettings.mousePause { return .mouse }
        return nil
    }

    /// Global key events only arrive once Accessibility is trusted, and a monitor installed before that
    /// may never receive them, so reinstall it when trust is granted.
    func accessibilityTrustChanged(_ trusted: Bool) {
        guard trusted else { return }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        installGlobalMonitor()
    }

    private func installGlobalMonitor() {
        guard globalMonitor == nil else { return }
        let mask = Self.typingEvents.union(Self.mouseEvents)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated {
                self?.record(type)
            }
        }
        if globalMonitor == nil {
            Self.logger.error("Could not install global event monitor")
        }
    }

    /// Covers events delivered to our own windows, which global monitors don't see.
    private func installLocalMonitor() {
        let mask = Self.typingEvents.union(Self.mouseEvents)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated {
                self?.record(type)
            }
            return event
        }
    }

    private func record(_ type: NSEvent.EventType) {
        let now = Self.now()
        switch type {
        case .keyDown, .flagsChanged:
            lastTyping = now
        case .mouseMoved:
            if now >= ignoreMouseMovesUntil { lastMouse = now }
        case .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
             .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            lastMouse = now
        default:
            break
        }
    }

    private static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
