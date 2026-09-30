import SwiftUI

/// The screen as a rectangle showing every grid dot, how far the fitted map lands from it, and optionally the live gaze point.
struct GridQualityMap: View {
    let grid: [GridSample]
    let model: GazeModel?
    /// Display width divided by height.
    let aspect: CGFloat
    var width: CGFloat = 240
    /// Live gaze estimate, 0...1 from the top-left.
    var gaze: CGPoint?

    /// Miss, as a share of the screen, above which a dot is shown as fair and as poor.
    private static let fairMiss = 0.08
    private static let poorMiss = 0.15

    private var height: CGFloat { width / max(aspect, 0.1) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.secondary.opacity(0.12))
            Rectangle().strokeBorder(Color.secondary.opacity(0.5))
            ForEach(Array(grid.enumerated()), id: \.offset) { index, sample in
                dot(index: index, sample: sample)
            }
            if let gaze {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 14, height: 14)
                    .position(point(min(max(gaze.x, -0.05), 1.05), min(max(gaze.y, -0.05), 1.05)))
            }
        }
        .frame(width: width, height: height)
        .clipShape(Rectangle())
    }

    @ViewBuilder
    private func dot(index: Int, sample: GridSample) -> some View {
        let target = point(sample.x, sample.y)
        let dropped = model?.droppedIndices.contains(index) ?? false
        let miss = model.flatMap { $0.misses.indices.contains(index) ? $0.misses[index] : nil }
        let color = Self.color(miss: miss, dropped: dropped)
        if let model {
            // Line from the dot to where the fitted map puts the head pose recorded for it.
            let landed = model.predict(yaw: sample.yaw, pitch: sample.pitch)
            Path { path in
                path.move(to: target)
                path.addLine(to: point(landed.x, landed.y))
            }
            .stroke(color.opacity(0.7), lineWidth: 1)
        }
        Circle()
            .strokeBorder(color, lineWidth: dropped ? 2 : 1.5)
            .background(Circle().fill(dropped ? Color.clear : color.opacity(0.35)))
            .frame(width: 10, height: 10)
            .position(target)
        if dropped {
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(color)
                .position(target)
        }
    }

    private func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x * width, y: y * height)
    }

    private static func color(miss: Double?, dropped: Bool) -> Color {
        if dropped { return .red }
        guard let miss else { return .secondary }
        if miss >= poorMiss { return .red }
        if miss >= fairMiss { return .orange }
        return .green
    }
}

/// Explains the colors in `GridQualityMap`.
struct GridQualityLegend: View {
    var body: some View {
        Text("Dots: green is predicted well from the others, orange is off, red is far off. ✕ marks dots ignored as outliers. Lines show where the fitted map puts each dot's recorded head pose.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 240, alignment: .leading)
    }
}
