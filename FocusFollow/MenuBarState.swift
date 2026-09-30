import SwiftUI

/// What the menu bar icon shows. Computed in one place from `AppState`.
enum MenuBarState: Equatable {
    case active
    case noFace
    case pausedByUser
    case systemSuspended
    /// Missing permission, camera problem, or no calibration for the current displays.
    case needsAttention

    var symbolName: String {
        switch self {
        case .active: "eye"
        case .noFace: "eye.trianglebadge.exclamationmark"
        case .pausedByUser: "eye.slash"
        case .systemSuspended: "moon"
        case .needsAttention: "exclamationmark.triangle"
        }
    }
}

extension AppState {
    var menuBarState: MenuBarState {
        if isUserPaused { return .pausedByUser }
        if isSystemSuspended { return .systemSuspended }
        if !focus.accessibilityTrusted || focus.calibration == nil { return .needsAttention }
        switch tracker.status {
        case .permissionDenied, .noCamera, .failed: return .needsAttention
        case .running: return !tracker.hasFace ? .noFace : .active
        case .stopped, .requestingPermission: return .active
        }
    }
}

extension MenuBarState {
    /// Icon badge color in the popover.
    var tint: Color {
        switch self {
        case .active: .accentColor
        case .noFace, .needsAttention: .orange
        case .pausedByUser, .systemSuspended: .secondary
        }
    }
}
