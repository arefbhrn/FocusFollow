import CoreGraphics
import Foundation

/// A visible window as the window server reports it. Bounds are in global CoreGraphics coordinates.
struct WindowCandidate: Sendable, Equatable {
    var number: Int
    var pid: pid_t
    var bounds: CGRect
    /// `false` for windows that can hide others but must never be focused by gaze, such as our own.
    var selectable = true
}

/// Chooses the window the gaze points at, or none when the point is too close to a border to be sure.
enum WindowPicker {
    /// Never shrink a window by more than this share of its size on one side, so every window keeps a core.
    static let maximumInsetShare = 0.3

    /// - Parameters:
    ///   - point: estimated gaze point in global coordinates.
    ///   - windows: candidates on the screen, ordered front to back.
    ///   - margin: how far inside a window's edge the point must be, in points. Scale it with the gaze error.
    ///   - screen: the display's bounds; a window edge on the display edge gets no margin, since nothing borders it.
    static func pick(at point: CGPoint, in windows: [WindowCandidate], margin: CGSize, screen: CGRect) -> WindowCandidate? {
        // The topmost window under the point is the one the user sees there, even if it is not selectable.
        guard let top = windows.first(where: { $0.bounds.contains(point) }), top.selectable else { return nil }
        return core(of: top.bounds, margin: margin, screen: screen).contains(point) ? top : nil
    }

    /// The window's frame pulled in by `margin` on every side that faces another window or open desktop.
    static func core(of bounds: CGRect, margin: CGSize, screen: CGRect) -> CGRect {
        let insetX = min(margin.width, bounds.width * maximumInsetShare)
        let insetY = min(margin.height, bounds.height * maximumInsetShare)
        // Windows stop short of the menu bar and the Dock, and a strip this thin can't hold another window,
        // so a window edge this close to the display edge counts as being on it.
        let edge = 100.0
        let left = abs(bounds.minX - screen.minX) <= edge ? 0 : insetX
        let right = abs(bounds.maxX - screen.maxX) <= edge ? 0 : insetX
        let top = abs(bounds.minY - screen.minY) <= edge ? 0 : insetY
        let bottom = abs(bounds.maxY - screen.maxY) <= edge ? 0 : insetY
        return CGRect(
            x: bounds.minX + left,
            y: bounds.minY + top,
            width: max(bounds.width - left - right, 0),
            height: max(bounds.height - top - bottom, 0)
        )
    }
}

/// Confirms a window only after it has been the pick for `delay` without interruption.
struct WindowDwell {
    private var candidate: Int?
    private var since: TimeInterval = 0

    /// Returns the window number once it has been stable for `delay`. `nil` number means nothing is picked.
    mutating func update(_ number: Int?, at now: TimeInterval, delay: TimeInterval) -> Int? {
        guard let number else {
            candidate = nil
            return nil
        }
        if candidate != number {
            candidate = number
            since = now
        }
        return now - since >= delay ? number : nil
    }

    mutating func reset() {
        candidate = nil
    }
}
