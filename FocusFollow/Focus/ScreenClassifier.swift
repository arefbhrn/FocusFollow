import Foundation

/// Maps a head pose to the calibrated screen it is closest to.
struct ScreenClassifier: Sendable {
    enum Result: Sendable, Equatable {
        case screen(String)
        case away
    }

    struct Evaluation: Sendable, Equatable {
        /// Normalized distance to every screen, in standard deviations.
        var distances: [String: Double]
        var result: Result
    }

    /// Stats per screen ID.
    var stats: [String: ScreenStats]
    /// Floor for per-axis standard deviation in degrees, so a very steady calibration doesn't get brittle.
    var minimumStd = 2.0
    /// Beyond this normalized distance from every screen the pose counts as away.
    var awayThreshold = 3.0

    init(stats: [String: ScreenStats]) {
        self.stats = stats
    }

    func evaluate(_ pose: HeadPose) -> Evaluation {
        var distances: [String: Double] = [:]
        for (id, screen) in stats {
            let yaw = (pose.yaw - screen.meanYaw) / max(screen.stdYaw, minimumStd)
            let pitch = (pose.pitch - screen.meanPitch) / max(screen.stdPitch, minimumStd)
            distances[id] = (yaw * yaw + pitch * pitch).squareRoot()
        }
        // Sorted so ties resolve deterministically.
        let nearest = distances.sorted { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }.first
        guard let nearest, nearest.value <= awayThreshold else {
            return Evaluation(distances: distances, result: .away)
        }
        return Evaluation(distances: distances, result: .screen(nearest.key))
    }
}

/// Only confirms a classification after it has been stable for `delay`.
struct DwellFilter: Sendable {
    var delay: TimeInterval
    private(set) var confirmed: ScreenClassifier.Result?
    private var candidate: ScreenClassifier.Result?
    private var candidateSince: TimeInterval = 0

    init(delay: TimeInterval) {
        self.delay = delay
    }

    /// `observed` is `nil` when there is no face; that keeps the confirmed value but restarts the wait.
    /// Returns the new confirmed value when it just changed.
    mutating func update(_ observed: ScreenClassifier.Result?, at now: TimeInterval) -> ScreenClassifier.Result? {
        guard let observed, observed != confirmed else {
            candidate = nil
            return nil
        }
        if candidate != observed {
            candidate = observed
            candidateSince = now
        }
        guard now - candidateSince >= delay else { return nil }
        confirmed = observed
        candidate = nil
        return observed
    }

    mutating func reset() {
        confirmed = nil
        candidate = nil
    }
}
