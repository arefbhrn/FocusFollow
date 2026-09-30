import Foundation
import Observation
import OSLog

/// Walks through the screens one by one and records head-pose samples for each.
@MainActor
@Observable
final class CalibrationSession {
    enum Phase: Equatable {
        case idle
        /// Giving the user time to turn their head; samples are ignored.
        case settling
        case collecting
        case finished
    }

    /// Seconds of face-detected time collected per screen.
    static let collectDuration: TimeInterval = 20
    /// Seconds to wait after showing the prompt before collecting.
    static let settleDuration: TimeInterval = 2
    static let maxStoredSamples = 300
    private static let tickInterval = Duration.milliseconds(66)

    private static let logger = Logger(subsystem: "com.arefbhrn.focusfollow", category: "calibration")

    private(set) var phase = Phase.idle
    private(set) var layout = DisplayLayout(displays: [])
    private(set) var index = 0
    /// 0...1 for the current screen.
    private(set) var progress = 0.0
    private(set) var faceVisible = false
    private(set) var message: String?
    /// Screens calibrated so far in this run.
    private(set) var completed: [ScreenCalibration] = []
    private(set) var result: Calibration?

    /// Called once when a run finishes with at least one calibrated screen.
    @ObservationIgnored var onFinish: (@MainActor (Calibration) -> Void)?

    @ObservationIgnored private let tracker: HeadTracker
    @ObservationIgnored private let overlay = CalibrationOverlay()
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var samples: [PoseSample] = []
    @ObservationIgnored private var collected: TimeInterval = 0
    @ObservationIgnored private var phaseElapsed: TimeInterval = 0
    @ObservationIgnored private var lastTick: TimeInterval = 0

    init(tracker: HeadTracker) {
        self.tracker = tracker
    }

    var isActive: Bool {
        phase == .settling || phase == .collecting
    }

    var currentDisplay: DisplayInfo? {
        layout.displays.indices.contains(index) ? layout.displays[index] : nil
    }

    func start(layout: DisplayLayout) {
        cancel()
        guard !layout.displays.isEmpty else {
            message = "No displays found."
            return
        }
        self.layout = layout
        beginScreen(0)
    }

    /// Restart the current screen.
    func redo() {
        guard isActive else { return }
        beginScreen(index)
    }

    /// Go back and redo the previous screen.
    func back() {
        guard isActive, index > 0 else { return }
        let previous = layout.displays[index - 1].id
        completed.removeAll { $0.id == previous }
        beginScreen(index - 1)
    }

    func skip() {
        guard isActive else { return }
        advance()
    }

    func cancel() {
        stopLoop()
        overlay.hide()
        phase = .idle
        completed = []
        result = nil
        message = nil
        progress = 0
    }

    private func beginScreen(_ newIndex: Int) {
        index = newIndex
        phase = .settling
        samples = []
        collected = 0
        phaseElapsed = 0
        progress = 0
        faceVisible = false
        message = nil
        lastTick = ProcessInfo.processInfo.systemUptime

        if let display = currentDisplay {
            overlay.model.title = layout.label(for: display.id)
            overlay.model.detail = "Get ready…"
            overlay.model.progress = 0
            overlay.show(on: display)
        }
        startLoop()
    }

    private func startLoop() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: Self.tickInterval)
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(now - lastTick, 0.5)
        lastTick = now

        switch phase {
        case .settling:
            phaseElapsed += dt
            if phaseElapsed >= Self.settleDuration {
                phase = .collecting
            }
        case .collecting:
            if let pose = tracker.pose {
                faceVisible = true
                let sample = PoseSample(yaw: pose.yaw, pitch: pose.pitch)
                if sample != samples.last {
                    samples.append(sample)
                }
                collected += dt
            } else {
                faceVisible = false
            }
            progress = min(collected / Self.collectDuration, 1)
            overlay.model.progress = progress
            overlay.model.detail = faceVisible ? "Keep looking at this screen" : "No face detected"
            if collected >= Self.collectDuration {
                completeCurrent()
            }
        case .idle, .finished:
            break
        }
    }

    private func completeCurrent() {
        guard let display = currentDisplay else { return }
        guard let stats = ScreenStats.compute(from: samples) else {
            message = "Not enough samples. Trying this screen again."
            beginScreen(index)
            return
        }
        Self.logger.info("Calibrated \(display.id, privacy: .public): yaw \(stats.meanYaw, format: .fixed(precision: 1)) pitch \(stats.meanPitch, format: .fixed(precision: 1)) n=\(stats.sampleCount)")
        completed.removeAll { $0.id == display.id }
        completed.append(ScreenCalibration(
            id: display.id,
            name: layout.label(for: display.id),
            stats: stats,
            samples: Self.downsample(samples, to: Self.maxStoredSamples)
        ))
        advance()
    }

    private func advance() {
        if index + 1 < layout.displays.count {
            beginScreen(index + 1)
        } else {
            finish()
        }
    }

    private func finish() {
        stopLoop()
        overlay.hide()
        let ordered = layout.displays.compactMap { display in
            completed.first { $0.id == display.id }
        }
        guard !ordered.isEmpty else {
            phase = .idle
            message = "No screens were calibrated."
            return
        }
        let calibration = Calibration(arrangementKey: layout.key, createdAt: Date(), screens: ordered)
        result = calibration
        phase = .finished
        onFinish?(calibration)
    }

    static func downsample(_ samples: [PoseSample], to limit: Int) -> [PoseSample] {
        guard samples.count > limit, limit > 0 else { return samples }
        return (0..<limit).map { samples[$0 * samples.count / limit] }
    }
}
