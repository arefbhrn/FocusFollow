import SwiftUI

struct GridProgressView: View {
    let session: GridCalibrationSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Screen \(min(session.displayIndex + 1, session.displays.count)) of \(session.displays.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let display = session.currentDisplay {
                Text(session.layout.label(for: display.id)).font(.title2.bold())
            }
            Text("Point \(session.targetIndex + 1) of \(GridCalibrationSession.targets.count)")
            Text(session.faceVisible || session.phase == .settling
                 ? "Look at the dot on the highlighted screen, moving your head the way you naturally would."
                 : "No face detected. Face the camera.")
            ProgressView(value: session.progress)
            if let message = session.message {
                Text(message).foregroundStyle(.orange)
            }
            HStack {
                Button("Cancel", role: .cancel) { session.cancel() }
                Spacer()
            }
        }
    }
}

struct GridSummaryView: View {
    let focus: FocusController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gaze grid saved").font(.title2.bold())
            VStack(alignment: .leading, spacing: 14) {
                ForEach(focus.gridSession.displays) { display in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(focus.layout.label(for: display.id)).bold()
                            Spacer()
                            if let model = focus.gazeModels[display.id] {
                                Text("typical error \(model.gateError, format: .percent.precision(.fractionLength(0)))")
                            } else {
                                Text("not usable: move your head more toward each dot")
                                    .foregroundStyle(.orange)
                            }
                        }
                        if let model = focus.gazeModels[display.id], !model.droppedIndices.isEmpty {
                            Text("\(model.droppedIndices.count) of \(model.misses.count) dots ignored as outliers (\(model.error.formatted(.percent.precision(.fractionLength(0)))) without them)")
                                .foregroundStyle(.secondary)
                        }
                        if let grid = focus.gazeGrid(for: display.id) {
                            GridQualityMap(
                                grid: grid,
                                model: focus.gazeModels[display.id],
                                aspect: aspect(of: display),
                                // Fit a 200×110 box so a few screens, even a portrait one, don't outgrow the window.
                                width: min(200, 110 * aspect(of: display))
                            )
                        }
                    }
                }
            }
            .font(.caption)
            GridQualityLegend()
            Text("Lower is better. The debug window shows the estimated gaze point live.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Button("Recalibrate") { focus.startGridCalibration() }
                Spacer()
                Button("Done") { focus.gridSession.cancel() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private extension GridSummaryView {
    func aspect(of display: DisplayInfo) -> CGFloat {
        display.bounds.width / max(display.bounds.height, 1)
    }
}
