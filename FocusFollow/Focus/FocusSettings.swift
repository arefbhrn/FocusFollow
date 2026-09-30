import Foundation

/// Tunable values for screen focus. A settings UI comes in Phase 4.
enum FocusSettings {
    static let dwellDelayKey = "dwellDelay"
    static let defaultDwellDelay: TimeInterval = 0.3
    static let typingPauseKey = "typingPause"
    static let defaultTypingPause: TimeInterval = 3
    static let mousePauseKey = "mousePause"
    static let defaultMousePause: TimeInterval = 1.5

    /// How long a screen must be the stable classification before focus follows.
    static var dwellDelay: TimeInterval {
        let value = UserDefaults.standard.double(forKey: dwellDelayKey)
        return value > 0 ? value : defaultDwellDelay
    }

    /// How long after the last keystroke switching stays held. 0 disables the hold.
    static var typingPause: TimeInterval {
        seconds(forKey: typingPauseKey, default: defaultTypingPause)
    }

    /// How long after the last mouse / trackpad activity switching stays held. 0 disables the hold.
    static var mousePause: TimeInterval {
        seconds(forKey: mousePauseKey, default: defaultMousePause)
    }

    private static func seconds(forKey key: String, default fallback: TimeInterval) -> TimeInterval {
        guard let value = UserDefaults.standard.object(forKey: key) as? Double, value >= 0 else { return fallback }
        return value
    }
}
