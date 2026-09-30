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
    /// Only filled in when eye detection is on and Vision found both pupils.
    var eyes: EyeOffset?

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

extension EyeOffset {
    /// Pupil position in each eye relative to the eye's bounding box, averaged over both eyes.
    /// `observation` must come from a landmarks request. `nil` if either eye or pupil is missing.
    init?(landmarks observation: VNFaceObservation, imageSize: CGSize) {
        guard let landmarks = observation.landmarks,
              let left = Self.offset(pupil: landmarks.leftPupil, eye: landmarks.leftEye, imageSize: imageSize),
              let right = Self.offset(pupil: landmarks.rightPupil, eye: landmarks.rightEye, imageSize: imageSize)
        else { return nil }
        self.init(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
    }

    private static func offset(
        pupil: VNFaceLandmarkRegion2D?,
        eye: VNFaceLandmarkRegion2D?,
        imageSize: CGSize
    ) -> CGPoint? {
        guard let pupil, let eye,
              let center = pupil.pointsInImage(imageSize: imageSize).first else { return nil }
        let outline = eye.pointsInImage(imageSize: imageSize)
        guard outline.count >= 4,
              let minX = outline.map(\.x).min(), let maxX = outline.map(\.x).max(),
              let minY = outline.map(\.y).min(), let maxY = outline.map(\.y).max(),
              maxX - minX > 1 else { return nil }
        let width = maxX - minX
        return CGPoint(x: (center.x - (minX + maxX) / 2) / width, y: (center.y - (minY + maxY) / 2) / width)
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

/// Exponential moving average over eye offsets.
struct EyeSmoother {
    var alpha: Double
    private var value: EyeOffset?

    init(alpha: Double) {
        self.alpha = alpha
    }

    mutating func update(with sample: EyeOffset) -> EyeOffset {
        guard let value else {
            self.value = sample
            return sample
        }
        let next = EyeOffset(x: value.x + alpha * (sample.x - value.x), y: value.y + alpha * (sample.y - value.y))
        self.value = next
        return next
    }

    mutating func reset() {
        value = nil
    }
}
