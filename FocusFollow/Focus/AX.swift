import AppKit
import ApplicationServices

/// Thin wrappers over the Accessibility C API. `AXUIElement` isn't Sendable, so everything stays on the main actor.
@MainActor
enum AX {
    /// Keeps a hung target app from blocking the main thread for long.
    private static let messagingTimeout: Float = 0.3

    static func application(pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    static func focusedWindow(pid: pid_t) -> AXUIElement? {
        element(application(pid: pid), kAXFocusedWindowAttribute)
    }

    static func windows(pid: pid_t) -> [AXUIElement] {
        guard let windows = copy(application(pid: pid), kAXWindowsAttribute) as? [AnyObject] else { return [] }
        return windows.compactMap { item in
            guard CFGetTypeID(item) == AXUIElementGetTypeID() else { return nil }
            let window = unsafeBitCast(item, to: AXUIElement.self)
            AXUIElementSetMessagingTimeout(window, messagingTimeout)
            return window
        }
    }

    /// Window frame in global CoreGraphics coordinates. `nil` if the element is gone or not a window.
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = copy(window, kAXPositionAttribute),
              let sizeValue = copy(window, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position),
              AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Brings the window to the front and gives it keyboard focus.
    static func focus(window: AXUIElement, pid: pid_t) {
        let app = application(pid: pid)
        _ = NSRunningApplication(processIdentifier: pid)?.activate()
        _ = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, window)
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(parent, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = unsafeBitCast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return element
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
