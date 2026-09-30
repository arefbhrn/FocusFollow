import Foundation

/// Tunable values for screen focus. `SettingsView` edits them through `@AppStorage` with the same keys.
enum FocusSettings {
    static let dwellDelayKey = "dwellDelay"
    static let defaultDwellDelay: TimeInterval = 0.3
    static let typingPauseKey = "typingPause"
    static let defaultTypingPause: TimeInterval = 3
    static let mousePauseKey = "mousePause"
    static let defaultMousePause: TimeInterval = 1.5
    static let awayThresholdKey = "awayThreshold"
    static let defaultAwayThreshold = 3.0
    static let moveCursorKey = "moveCursor"
    static let defaultMoveCursor = true

    static let dwellDelayRange = 0.1...1.5
    static let typingPauseRange = 0.0...10.0
    static let mousePauseRange = 0.0...5.0
    static let awayThresholdRange = 1.5...6.0

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

    /// How far from a calibrated screen's center the head may point and still count as that screen,
    /// in standard deviations. Higher is more forgiving; lower treats more poses as away.
    static var awayThreshold: Double {
        guard let value = UserDefaults.standard.object(forKey: awayThresholdKey) as? Double,
              awayThresholdRange.contains(value) else { return defaultAwayThreshold }
        return value
    }

    /// Whether the cursor follows focus to the new screen.
    static var moveCursor: Bool {
        UserDefaults.standard.object(forKey: moveCursorKey) as? Bool ?? defaultMoveCursor
    }

    private static func seconds(forKey key: String, default fallback: TimeInterval) -> TimeInterval {
        guard let value = UserDefaults.standard.object(forKey: key) as? Double, value >= 0 else { return fallback }
        return value
    }
}
