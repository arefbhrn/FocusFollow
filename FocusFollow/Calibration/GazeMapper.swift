import CoreGraphics
import Foundation

/// How far each pupil sits from the middle of its eye, averaged over both eyes and divided by the eye width.
/// Image axes: +x is toward the right of the camera image, +y is up.
struct EyeOffset: Sendable, Codable, Equatable {
    var x: Double
    var y: Double
}

/// One grid target and the head pose (and eye offset, when it was detected) measured while looking at it.
struct GridSample: Sendable, Codable, Equatable {
    /// Target position on the screen, 0...1 from the top-left corner.
    var x: Double
    var y: Double
    var yaw: Double
    var pitch: Double
    var eyeX: Double?
    var eyeY: Double?
}

/// What the gaze model reads from the tracker at one moment.
struct GazeInput: Sendable, Equatable {
    var yaw: Double
    var pitch: Double
    var eye: EyeOffset?

    init(pose: HeadPose, eye: EyeOffset?) {
        yaw = pose.yaw
        pitch = pose.pitch
        self.eye = eye
    }

    init(_ sample: GridSample) {
        yaw = sample.yaw
        pitch = sample.pitch
        if let x = sample.eyeX, let y = sample.eyeY {
            eye = EyeOffset(x: x, y: y)
        }
    }
}

/// Where on a screen the head points, 0...1 from the top-left. Values can fall outside the range.
struct GazeEstimate: Sendable, Equatable {
    var displayID: String
    var x: Double
    var y: Double
    /// The model that produced this point.
    var featureSet: GazeFeatureSet
}

/// Which inputs a gaze model uses.
enum GazeFeatureSet: String, CaseIterable, Sendable {
    /// Yaw and pitch.
    case head
    /// Yaw, pitch and their product.
    case headCross
    /// Yaw, pitch and the pupil offset.
    case headEyes

    var title: String {
        switch self {
        case .head: "Head"
        case .headCross: "Head + cross term"
        case .headEyes: "Head + eyes"
        }
    }

    /// The model inputs, or `nil` when this set needs eye data that is missing.
    func features(of input: GazeInput) -> [Double]? {
        switch self {
        case .head:
            return [input.yaw, input.pitch]
        case .headCross:
            return [input.yaw, input.pitch, input.yaw * input.pitch / 10]
        case .headEyes:
            guard let eye = input.eye else { return nil }
            return [input.yaw, input.pitch, eye.x, eye.y]
        }
    }
}

/// Linear map from tracker inputs to a point on one screen, fitted to its grid samples.
struct GazeModel: Sendable, Equatable {
    /// Samples beyond the number of fitted parameters that leave-one-out needs.
    private static let spareSamples = 2
    /// Smallest head movement (degrees, max minus min) the grid must show on each axis for the fit to mean anything.
    static let minimumYawRange = 2.0
    static let minimumPitchRange = 1.0
    /// A fit this far off (fraction of the screen, leave-one-out) is noise or a near-degenerate grid, not a usable map.
    static let maximumError = 0.4

    let featureSet: GazeFeatureSet
    private let fit: Fit
    let sampleCount: Int
    /// Leave-one-out RMS distance between predicted and true target, as a fraction of the screen.
    let error: Double

    /// `nil` when the input lacks something this model needs (for example no eye data).
    func predict(_ input: GazeInput) -> CGPoint? {
        guard let features = featureSet.features(of: input) else { return nil }
        return fit.predict(features)
    }

    /// `nil` when there are too few samples, the head barely moved across the grid, or the fit is too noisy.
    static func fit(_ samples: [GridSample], featureSet: GazeFeatureSet) -> GazeModel? {
        let rows = samples.compactMap { sample -> (features: [Double], x: Double, y: Double)? in
            featureSet.features(of: GazeInput(sample)).map { ($0, sample.x, sample.y) }
        }
        // Eye data can be missing for some targets; the set then needs all of them.
        guard rows.count == samples.count,
              let width = rows.first?.features.count,
              rows.count >= width + 1 + spareSamples,
              range(of: samples.map(\.yaw)) >= minimumYawRange,
              range(of: samples.map(\.pitch)) >= minimumPitchRange,
              let full = Fit.solve(rows) else { return nil }

        var squaredError = 0.0
        for index in rows.indices {
            var rest = rows
            let held = rest.remove(at: index)
            guard let partial = Fit.solve(rest) else { return nil }
            let point = partial.predict(held.features)
            let dx = point.x - held.x
            let dy = point.y - held.y
            squaredError += dx * dx + dy * dy
        }
        let error = (squaredError / Double(rows.count)).squareRoot()
        guard error <= maximumError else { return nil }
        return GazeModel(featureSet: featureSet, fit: full, sampleCount: rows.count, error: error)
    }

    private static func range(of values: [Double]) -> Double {
        guard let low = values.min(), let high = values.max() else { return 0 }
        return high - low
    }

    /// Least squares on standardized inputs, so degrees and eye offsets of very different size fit together.
    fileprivate struct Fit: Equatable, Sendable {
        var mean: [Double]
        var scale: [Double]
        /// Intercept first, then one per input.
        var x: [Double]
        var y: [Double]

        func predict(_ features: [Double]) -> CGPoint {
            var px = x[0]
            var py = y[0]
            for i in features.indices {
                let z = (features[i] - mean[i]) / scale[i]
                px += x[i + 1] * z
                py += y[i + 1] * z
            }
            return CGPoint(x: px, y: py)
        }

        static func solve(_ rows: [(features: [Double], x: Double, y: Double)]) -> Fit? {
            guard let width = rows.first?.features.count else { return nil }
            let n = Double(rows.count)
            var mean = [Double](repeating: 0, count: width)
            for row in rows { for i in 0..<width { mean[i] += row.features[i] / n } }
            var scale = [Double](repeating: 0, count: width)
            for row in rows { for i in 0..<width { scale[i] += pow(row.features[i] - mean[i], 2) / n } }
            scale = scale.map { max($0.squareRoot(), 1e-6) }

            let k = width + 1
            var ata = [[Double]](repeating: [Double](repeating: 0, count: k), count: k)
            var atx = [Double](repeating: 0, count: k)
            var aty = [Double](repeating: 0, count: k)
            for row in rows {
                var f = [1.0]
                for i in 0..<width { f.append((row.features[i] - mean[i]) / scale[i]) }
                for i in 0..<k {
                    for j in 0..<k { ata[i][j] += f[i] * f[j] }
                    atx[i] += f[i] * row.x
                    aty[i] += f[i] * row.y
                }
            }
            // A light ridge keeps near-collinear inputs solvable; it is tiny next to the standardized variances.
            for i in 1..<k { ata[i][i] += 1e-3 }
            guard let cx = gauss(ata, atx), let cy = gauss(ata, aty) else { return nil }
            return Fit(mean: mean, scale: scale, x: cx, y: cy)
        }

        /// Gaussian elimination with partial pivoting. `nil` for a singular system.
        private static func gauss(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
            let n = rhs.count
            var a = zip(matrix, rhs).map { $0 + [$1] }
            for column in 0..<n {
                guard let pivot = (column..<n).max(by: { abs(a[$0][column]) < abs(a[$1][column]) }),
                      abs(a[pivot][column]) > 1e-9 else { return nil }
                a.swapAt(column, pivot)
                for row in (column + 1)..<n {
                    let factor = a[row][column] / a[column][column]
                    for j in column...n { a[row][j] -= factor * a[column][j] }
                }
            }
            var solution = [Double](repeating: 0, count: n)
            for row in stride(from: n - 1, through: 0, by: -1) {
                var sum = a[row][n]
                for j in (row + 1)..<n { sum -= a[row][j] * solution[j] }
                solution[row] = sum / a[row][row]
            }
            return solution
        }
    }
}
