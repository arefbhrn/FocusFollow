import AVFoundation
import OSLog
import Vision

private let logger = Logger(subsystem: "com.arefbhrn.focusfollow", category: "camera")

enum CameraError: LocalizedError {
    case noCamera
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .noCamera: "No camera found."
        case .cannotAddInput: "The camera could not be opened."
        case .cannotAddOutput: "The camera output could not be configured."
        }
    }
}

/// Owns the capture session and runs Vision on each frame.
///
/// Session configuration is confined to `sessionQueue`, frame processing to `videoQueue`.
/// Frames are processed in memory and dropped right away.
final class CameraPipeline: NSObject, @unchecked Sendable {
    static let targetFrameRate = 15.0

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.arefbhrn.focusfollow.session")
    private let videoQueue = DispatchQueue(label: "com.arefbhrn.focusfollow.video", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var isOutputAdded = false

    // videoQueue only
    private let faceRequest: VNDetectFaceRectanglesRequest
    private var lastFrameTime = CMTime.invalid
    /// Slightly under 1/15 s so timestamp jitter doesn't halve the rate.
    private let minFrameInterval = CMTime(value: 1, timescale: 16)

    private let onFrame: @Sendable (FrameResult) -> Void

    init(onFrame: @escaping @Sendable (FrameResult) -> Void) {
        self.onFrame = onFrame
        let request = VNDetectFaceRectanglesRequest()
        // Revision 3 reports yaw, pitch, and roll.
        request.revision = VNDetectFaceRectanglesRequestRevision3
        faceRequest = request
        super.init()
    }

    static func availableCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    static func device(for uniqueID: String?) -> AVCaptureDevice? {
        if let uniqueID, let device = AVCaptureDevice(uniqueID: uniqueID) {
            return device
        }
        return AVCaptureDevice.default(for: .video) ?? availableCameras().first
    }

    /// Starts capturing from the given camera, or switches to it if already running.
    /// Returns the unique ID of the camera in use.
    func start(cameraID: String?) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    let device = try self.configure(cameraID: cameraID)
                    if !self.session.isRunning {
                        self.session.startRunning()
                    }
                    continuation.resume(returning: device.uniqueID)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func configure(cameraID: String?) throws -> AVCaptureDevice {
        guard let device = Self.device(for: cameraID) else { throw CameraError.noCamera }
        if currentInput?.device.uniqueID == device.uniqueID {
            return device
        }

        session.beginConfiguration()
        do {
            if let currentInput {
                session.removeInput(currentInput)
                self.currentInput = nil
            }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
            session.addInput(input)
            currentInput = input

            if session.canSetSessionPreset(.hd1280x720) {
                session.sessionPreset = .hd1280x720
            }

            if !isOutputAdded {
                output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ]
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: videoQueue)
                guard session.canAddOutput(output) else { throw CameraError.cannotAddOutput }
                session.addOutput(output)
                isOutputAdded = true
            }
        } catch {
            session.commitConfiguration()
            throw error
        }
        session.commitConfiguration()

        limitFrameRate(of: device)
        logger.info("Using camera \(device.localizedName, privacy: .public)")
        return device
    }

    /// Caps the camera frame rate where supported. `captureOutput` also throttles as a fallback.
    private func limitFrameRate(of device: AVCaptureDevice) {
        let fps = Self.targetFrameRate
        let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.minFrameRate <= fps && fps <= $0.maxFrameRate
        }
        guard supported else { return }
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            device.unlockForConfiguration()
        } catch {
            logger.error("Could not set frame rate: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension CameraPipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if lastFrameTime.isValid, CMTimeSubtract(time, lastFrameTime) < minFrameInterval {
            return
        }
        lastFrameTime = time

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )

        var face: FaceSample?
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
            try handler.perform([faceRequest])
            // The largest face is most likely the person at the Mac.
            if let observation = faceRequest.results?.max(by: { area($0) < area($1) }) {
                face = FaceSample(observation)
            }
        } catch {
            logger.error("Face detection failed: \(error.localizedDescription, privacy: .public)")
        }

        onFrame(FrameResult(face: face, imageSize: imageSize, timestamp: time.seconds))
    }

    private func area(_ observation: VNFaceObservation) -> CGFloat {
        observation.boundingBox.width * observation.boundingBox.height
    }
}
