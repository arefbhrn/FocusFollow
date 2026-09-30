import Foundation

/// Tunable values for screen focus. A settings UI comes in Phase 4.
enum FocusSettings {
    static let dwellDelayKey = "dwellDelay"
    static let defaultDwellDelay: TimeInterval = 0.3

    /// How long a screen must be the stable classification before focus follows.
    static var dwellDelay: TimeInterval {
        let value = UserDefaults.standard.double(forKey: dwellDelayKey)
        return value > 0 ? value : defaultDwellDelay
    }
}
