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
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                ForEach(focus.gridSession.displays) { display in
                    GridRow {
                        Text(focus.layout.label(for: display.id))
                        if let model = focus.gazeModels[display.id] {
                            Text("typical error \(model.error, format: .percent.precision(.fractionLength(0))) of the screen")
                        } else {
                            Text("not usable: move your head more toward each dot")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .font(.caption)
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
