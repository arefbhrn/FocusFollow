/// Why focus switching is currently held back.
enum HoldReason: Sendable, Equatable {
    case userPaused
    case typing
    case mouse
    case suspended(SystemSuspension)

    var label: String {
        switch self {
        case .userPaused: "Paused"
        case .typing: "Held: typing"
        case .mouse: "Held: mouse"
        case .suspended(let reason): "Suspended: \(reason.label)"
        }
    }
}
