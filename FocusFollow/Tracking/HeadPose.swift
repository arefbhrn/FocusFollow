import CoreGraphics
import Vision

/// Head orientation in degrees, as reported by Vision.
struct HeadPose: Sendable, Equatable {
    var yaw: Double
    var pitch: Double
    var roll: Double
}

/// The most prominent face in one camera frame.
struct FaceSample: Sendable {
    var pose: HeadPose
    /// Normalized to the image, Vision coordinates (origin bottom-left).
    var boundingBox: CGRect
    var confidence: Float

    init(_ observation: VNFaceObservation) {
        func degrees(_ radians: NSNumber?) -> Double {
            (radians?.doubleValue ?? 0) * 180 / .pi
        }
        pose = HeadPose(
            yaw: degrees(observation.yaw),
            pitch: degrees(observation.pitch),
            roll: degrees(observation.roll)
        )
        boundingBox = observation.boundingBox
        confidence = observation.confidence
    }
}

/// Result of processing one camera frame. Frames themselves are never kept.
struct FrameResult: Sendable {
    var face: FaceSample?
    var imageSize: CGSize
    /// Presentation timestamp in seconds.
    var timestamp: Double
}

/// Exponential moving average over head poses.
struct PoseSmoother {
    /// Weight of the newest sample, 0...1. Lower is smoother but laggier.
    var alpha: Double
    private(set) var value: HeadPose?

    init(alpha: Double = 0.3) {
        self.alpha = alpha
    }

    mutating func update(with sample: HeadPose) -> HeadPose {
        guard let value else {
            self.value = sample
            return sample
        }
        let next = HeadPose(
            yaw: value.yaw + alpha * (sample.yaw - value.yaw),
            pitch: value.pitch + alpha * (sample.pitch - value.pitch),
            roll: value.roll + alpha * (sample.roll - value.roll)
        )
        self.value = next
        return next
    }

    mutating func reset() {
        value = nil
    }
}
