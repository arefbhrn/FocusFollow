import AVFoundation
import Observation

struct CameraInfo: Identifiable, Hashable {
    let id: String
    let name: String
}

@MainActor
@Observable
final class HeadTracker {
    enum Status: Equatable {
        case stopped
        case requestingPermission
        case permissionDenied
        case noCamera
        case running
        case failed(String)
    }

    private enum Keys {
        static let camera = "cameraID"
        static let smoothing = "poseSmoothing"
    }

    private(set) var status = Status.stopped
    private(set) var cameras: [CameraInfo] = []
    /// Camera the user picked. `nil` means the system default.
    var selectedCameraID: String? {
        didSet {
            guard selectedCameraID != oldValue else { return }
            UserDefaults.standard.set(selectedCameraID, forKey: Keys.camera)
            if status == .running {
                Task { await runPipeline() }
            }
        }
    }
    /// Camera actually in use.
    private(set) var activeCameraID: String?

    private(set) var rawPose: HeadPose?
    private(set) var pose: HeadPose?
    private(set) var faceBox: CGRect?
    private(set) var imageSize = CGSize.zero
    private(set) var framesPerSecond = 0.0

    /// Weight of the newest sample in the EMA, 0.05...1.
    var smoothing: Double {
        didSet {
            smoother.alpha = smoothing
            UserDefaults.standard.set(smoothing, forKey: Keys.smoothing)
        }
    }

    var session: AVCaptureSession { pipeline.session }

    @ObservationIgnored private let pipeline: CameraPipeline
    @ObservationIgnored private var smoother: PoseSmoother
    @ObservationIgnored private var wantsRunning = false
    @ObservationIgnored private var lastFrameTimestamp: Double?
    @ObservationIgnored private var frameTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let (frames, continuation) = AsyncStream.makeStream(
            of: FrameResult.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        pipeline = CameraPipeline { continuation.yield($0) }

        let defaults = UserDefaults.standard
        selectedCameraID = defaults.string(forKey: Keys.camera)
        let savedSmoothing = defaults.double(forKey: Keys.smoothing)
        let initialSmoothing = savedSmoothing > 0 ? savedSmoothing : 0.3
        smoothing = initialSmoothing
        smoother = PoseSmoother(alpha: initialSmoothing)

        frameTask = Task { [weak self] in
            for await frame in frames {
                self?.handle(frame)
            }
        }

        refreshCameras()
        observeCameraChanges()
    }

    func start() async {
        wantsRunning = true
        guard status != .running else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            status = .requestingPermission
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .permissionDenied
                return
            }
        default:
            status = .permissionDenied
            return
        }

        refreshCameras()
        await runPipeline()
    }

    func stop() {
        wantsRunning = false
        pipeline.stop()
        status = .stopped
        clearFaceState()
    }

    private func runPipeline() async {
        do {
            activeCameraID = try await pipeline.start(cameraID: selectedCameraID)
            guard wantsRunning else {
                pipeline.stop()
                return
            }
            if status != .running {
                status = .running
            }
            clearFaceState()
        } catch CameraError.noCamera {
            status = .noCamera
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func handle(_ frame: FrameResult) {
        guard status == .running else { return }

        if let last = lastFrameTimestamp, frame.timestamp > last {
            let instant = 1 / (frame.timestamp - last)
            framesPerSecond = framesPerSecond == 0 ? instant : framesPerSecond * 0.9 + instant * 0.1
        }
        lastFrameTimestamp = frame.timestamp
        imageSize = frame.imageSize

        if let face = frame.face {
            rawPose = face.pose
            pose = smoother.update(with: face.pose)
            faceBox = face.boundingBox
        } else {
            rawPose = nil
            pose = nil
            faceBox = nil
            smoother.reset()
        }
    }

    private func clearFaceState() {
        rawPose = nil
        pose = nil
        faceBox = nil
        framesPerSecond = 0
        lastFrameTimestamp = nil
        smoother.reset()
    }

    private func refreshCameras() {
        cameras = CameraPipeline.availableCameras().map {
            CameraInfo(id: $0.uniqueID, name: $0.localizedName)
        }
    }

    private func observeCameraChanges() {
        let names = [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.camerasChanged()
                }
            }
        }
    }

    private func camerasChanged() {
        refreshCameras()
        guard wantsRunning else { return }
        // Fall back if the active camera went away, return to the picked one when it's back,
        // or retry if none was available.
        let activeIsGone = !cameras.contains { $0.id == activeCameraID }
        let selectedIsBack = selectedCameraID != nil
            && selectedCameraID != activeCameraID
            && cameras.contains { $0.id == selectedCameraID }
        if activeIsGone || selectedIsBack || status == .noCamera {
            Task { await runPipeline() }
        }
    }
}
