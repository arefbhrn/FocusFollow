import Foundation

/// One smoothed pose reading taken while looking at a screen.
struct PoseSample: Sendable, Codable, Equatable {
    var yaw: Double
    var pitch: Double
}

struct ScreenStats: Sendable, Codable, Equatable {
    var meanYaw: Double
    var meanPitch: Double
    var stdYaw: Double
    var stdPitch: Double
    var sampleCount: Int

    static let minimumSamples = 10

    static func compute(from samples: [PoseSample]) -> ScreenStats? {
        guard samples.count >= minimumSamples else { return nil }
        let n = Double(samples.count)
        let meanYaw = samples.reduce(0) { $0 + $1.yaw } / n
        let meanPitch = samples.reduce(0) { $0 + $1.pitch } / n
        let varYaw = samples.reduce(0) { $0 + ($1.yaw - meanYaw) * ($1.yaw - meanYaw) } / n
        let varPitch = samples.reduce(0) { $0 + ($1.pitch - meanPitch) * ($1.pitch - meanPitch) } / n
        return ScreenStats(
            meanYaw: meanYaw,
            meanPitch: meanPitch,
            stdYaw: varYaw.squareRoot(),
            stdPitch: varPitch.squareRoot(),
            sampleCount: samples.count
        )
    }
}

struct ScreenCalibration: Sendable, Codable, Equatable, Identifiable {
    /// `DisplayInfo.id` of the calibrated screen.
    var id: String
    var name: String
    var stats: ScreenStats
    /// Downsampled, kept so later phases can refit without recalibrating.
    var samples: [PoseSample]
}

struct Calibration: Sendable, Codable, Equatable {
    var arrangementKey: String
    var createdAt: Date
    var screens: [ScreenCalibration]
}

/// Calibrations saved per display arrangement, as JSON in UserDefaults.
enum CalibrationStore {
    private static let defaultsKey = "calibrations"

    static func load(arrangementKey: String) -> Calibration? {
        loadAll()[arrangementKey]
    }

    static func save(_ calibration: Calibration) {
        var all = loadAll()
        all[calibration.arrangementKey] = calibration
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private static func loadAll() -> [String: Calibration] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Calibration].self, from: data)) ?? [:]
    }
}
