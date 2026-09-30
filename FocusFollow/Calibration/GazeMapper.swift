import CoreGraphics
import Foundation

/// One grid target and the head pose measured while looking at it.
struct GridSample: Sendable, Codable, Equatable {
    /// Target position on the screen, 0...1 from the top-left corner.
    var x: Double
    var y: Double
    var yaw: Double
    var pitch: Double
}

/// Where on a screen the head is pointing, 0...1 from the top-left. Values can fall outside the range.
struct GazeEstimate: Sendable, Equatable {
    var displayID: String
    var x: Double
    var y: Double
}

/// Linear map from head pose to a point on one screen, fitted to its grid samples.
struct GazeModel: Sendable, Equatable {
    static let minimumSamples = 5
    /// Smallest head movement (degrees, max minus min) the grid must show on each axis for the fit to mean anything.
    static let minimumYawRange = 2.0
    static let minimumPitchRange = 1.0
    /// A fit this far off (fraction of the screen, leave-one-out) is noise or a near-degenerate grid, not a usable map.
    static let maximumError = 0.4

    /// Coefficients for `[1, yaw, pitch]`.
    private let xCoefficients: [Double]
    private let yCoefficients: [Double]
    let sampleCount: Int
    /// Leave-one-out RMS distance between predicted and true target, as a fraction of the screen.
    let error: Double

    func predict(yaw: Double, pitch: Double) -> CGPoint {
        CGPoint(
            x: Self.evaluate(xCoefficients, yaw: yaw, pitch: pitch),
            y: Self.evaluate(yCoefficients, yaw: yaw, pitch: pitch)
        )
    }

    func predict(_ pose: HeadPose) -> CGPoint {
        predict(yaw: pose.yaw, pitch: pose.pitch)
    }

    /// `nil` when there are too few samples or the head barely moved across the grid.
    static func fit(_ samples: [GridSample]) -> GazeModel? {
        guard samples.count >= minimumSamples,
              range(of: samples.map(\.yaw)) >= minimumYawRange,
              range(of: samples.map(\.pitch)) >= minimumPitchRange,
              let full = solve(samples) else { return nil }

        var squaredError = 0.0
        for index in samples.indices {
            var rest = samples
            let held = rest.remove(at: index)
            guard let partial = solve(rest) else { return nil }
            let dx = evaluate(partial.x, yaw: held.yaw, pitch: held.pitch) - held.x
            let dy = evaluate(partial.y, yaw: held.yaw, pitch: held.pitch) - held.y
            squaredError += dx * dx + dy * dy
        }
        let error = (squaredError / Double(samples.count)).squareRoot()
        guard error <= maximumError else { return nil }
        return GazeModel(xCoefficients: full.x, yCoefficients: full.y, sampleCount: samples.count, error: error)
    }

    private static func evaluate(_ c: [Double], yaw: Double, pitch: Double) -> Double {
        c[0] + c[1] * yaw + c[2] * pitch
    }

    private static func range(of values: [Double]) -> Double {
        guard let low = values.min(), let high = values.max() else { return 0 }
        return high - low
    }

    /// Least squares through the normal equations; the ridge term only keeps them solvable.
    private static func solve(_ samples: [GridSample]) -> (x: [Double], y: [Double])? {
        let k = 3
        var ata = [[Double]](repeating: [Double](repeating: 0, count: k), count: k)
        var atx = [Double](repeating: 0, count: k)
        var aty = [Double](repeating: 0, count: k)
        for sample in samples {
            let f = [1.0, sample.yaw, sample.pitch]
            for i in 0..<k {
                for j in 0..<k { ata[i][j] += f[i] * f[j] }
                atx[i] += f[i] * sample.x
                aty[i] += f[i] * sample.y
            }
        }
        for i in 1..<k { ata[i][i] += 1e-6 }
        guard let x = gauss(ata, atx), let y = gauss(ata, aty) else { return nil }
        return (x, y)
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
