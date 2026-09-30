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
    /// A dot whose leave-one-out miss is this many times the typical (median) miss counts as an outlier.
    static let outlierFactor = 2.5
    /// ...and only when it also misses by more than this much of the screen, so a very clean grid drops nothing.
    static let minimumOutlierMiss = 0.06
    /// Never ignore more than this share of the dots. Keeps a systematic weakness (say, corners where the head
    /// really does not follow) from being hidden by dropping it; the ignored dots are still shown on the map.
    static let maximumDroppedShare = 0.12
    /// An ignored dot counts toward `gateError` with at most this miss, so one wild blink doesn't sink a good screen.
    static let ignoredMissCap = 0.3

    /// Coefficients for `[1, yaw, pitch]`.
    private let xCoefficients: [Double]
    private let yCoefficients: [Double]
    /// Dots the fit was made from, after ignoring outliers.
    let sampleCount: Int
    /// Leave-one-out RMS distance between predicted and true target over the dots used, as a fraction of the screen.
    /// Flattering when dots were ignored: they were chosen for missing the most.
    let error: Double
    /// Like `error`, but the ignored dots count too, each with its miss capped at `ignoredMissCap`. This is what
    /// decides whether a screen is accurate enough for windows and how wide the dead zone around borders is.
    let gateError: Double
    /// Indices (into the samples passed to `fit`) of dots ignored as outliers.
    let droppedIndices: [Int]
    /// Out-of-sample miss per sample passed to `fit`, as a share of the screen: leave-one-out for dots used,
    /// the distance from the final fit for ignored dots.
    let misses: [Double]

    func predict(yaw: Double, pitch: Double) -> CGPoint {
        CGPoint(
            x: Self.evaluate(xCoefficients, yaw: yaw, pitch: pitch),
            y: Self.evaluate(yCoefficients, yaw: yaw, pitch: pitch)
        )
    }

    func predict(_ pose: HeadPose) -> CGPoint {
        predict(yaw: pose.yaw, pitch: pose.pitch)
    }

    /// Fits the map, ignoring dots that miss far more than the rest (a blink, a glance away, a drifting posture).
    /// `nil` when there are too few samples, the head barely moved across the grid, or the fit is too noisy.
    static func fit(_ samples: [GridSample]) -> GazeModel? {
        guard samples.count >= minimumSamples, isUsable(samples) else { return nil }

        // Drop the worst outlier, refit, and repeat: one bad dot inflates the misses of all the others, so
        // judging them in a single pass would throw out good dots too.
        var keptIndices = Array(samples.indices)
        var dropped: [Int] = []
        let allowed = min(Int(Double(samples.count) * maximumDroppedShare), samples.count - minimumSamples)
        while dropped.count < allowed {
            guard let misses = leaveOneOutMisses(keptIndices.map { samples[$0] }) else {
                if dropped.isEmpty { return nil }
                break
            }
            let threshold = max(outlierFactor * median(misses), minimumOutlierMiss)
            guard let worst = misses.indices.max(by: { misses[$0] < misses[$1] }), misses[worst] > threshold else { break }
            var remaining = keptIndices
            let removed = remaining.remove(at: worst)
            guard isUsable(remaining.map { samples[$0] }) else { break }
            keptIndices = remaining
            dropped.append(removed)
        }
        let droppedSet = Set(dropped)
        let kept = keptIndices.map { samples[$0] }

        guard isUsable(kept), let keptMisses = leaveOneOutMisses(kept), let full = solve(kept) else { return nil }
        let error = rms(keptMisses)
        guard error <= maximumError else { return nil }

        var misses = [Double](repeating: 0, count: samples.count)
        for (position, index) in keptIndices.enumerated() { misses[index] = keptMisses[position] }
        for index in droppedSet {
            let sample = samples[index]
            let dx = evaluate(full.x, yaw: sample.yaw, pitch: sample.pitch) - sample.x
            let dy = evaluate(full.y, yaw: sample.yaw, pitch: sample.pitch) - sample.y
            misses[index] = (dx * dx + dy * dy).squareRoot()
        }
        let gateError = rms(misses.enumerated().map { index, miss in
            droppedSet.contains(index) ? min(miss, ignoredMissCap) : miss
        })
        return GazeModel(
            xCoefficients: full.x,
            yCoefficients: full.y,
            sampleCount: kept.count,
            error: error,
            gateError: gateError,
            droppedIndices: droppedSet.sorted(),
            misses: misses
        )
    }

    private static func rms(_ values: [Double]) -> Double {
        (values.reduce(0) { $0 + $1 * $1 } / Double(max(values.count, 1))).squareRoot()
    }

    private static func isUsable(_ samples: [GridSample]) -> Bool {
        samples.count >= minimumSamples
            && range(of: samples.map(\.yaw)) >= minimumYawRange
            && range(of: samples.map(\.pitch)) >= minimumPitchRange
    }

    /// For each sample, how far it lands from its target when the map is fitted to all the others.
    private static func leaveOneOutMisses(_ samples: [GridSample]) -> [Double]? {
        var misses: [Double] = []
        for index in samples.indices {
            var rest = samples
            let held = rest.remove(at: index)
            guard let partial = solve(rest) else { return nil }
            let dx = evaluate(partial.x, yaw: held.yaw, pitch: held.pitch) - held.x
            let dy = evaluate(partial.y, yaw: held.yaw, pitch: held.pitch) - held.y
            misses.append((dx * dx + dy * dy).squareRoot())
        }
        return misses
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
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
