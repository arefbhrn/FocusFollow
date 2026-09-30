/// Why focus switching is currently held back.
enum HoldReason: Sendable, Equatable {
    case userPaused
    case typing
    case mouse

    var label: String {
        switch self {
        case .userPaused: "Paused"
        case .typing: "Held: typing"
        case .mouse: "Held: mouse"
        }
    }
}
