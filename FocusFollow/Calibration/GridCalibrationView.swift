import SwiftUI

struct GridProgressView: View {
    let session: GridCalibrationSession

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            Text("Screen \(min(session.displayIndex + 1, session.displays.count)) of \(session.displays.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ProgressRing(progress: session.progress) {
                VStack(spacing: 0) {
                    Text("\(session.targetIndex + 1)")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("of \(GridCalibrationSession.targets.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 132, height: 132)
            if let display = session.currentDisplay {
                Text(session.layout.label(for: display.id)).font(.title3.weight(.semibold))
            }
            Label(statusText, systemImage: statusKind.symbol)
                .foregroundStyle(statusKind == .warning ? statusKind.color : .secondary)
                .multilineTextAlignment(.center)
            if let message = session.message {
                Text(message).font(.callout).foregroundStyle(.orange)
            }
            HStack {
                Button("Cancel", role: .cancel) { session.cancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statusKind: Theme.Status {
        session.faceVisible || session.phase == .settling ? .neutral : .warning
    }

    private var statusText: String {
        session.faceVisible || session.phase == .settling
            ? "Look at the dot, turning your head the way you naturally would."
            : "No face detected. Face the camera."
    }
}

struct GridSummaryView: View {
    let focus: FocusController

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            WindowHeader(
                symbol: "checkmark.seal.fill",
                title: "Gaze grid saved",
                subtitle: "Lower error means window focus can tell windows apart more reliably.",
                tint: .green
            )
            ForEach(focus.gridSession.displays) { display in
                DisplayGridCard(focus: focus, display: display)
            }
            GridQualityLegend()
            HStack {
                Button("Recalibrate") { focus.startGridCalibration() }
                Spacer()
                Button("Done") { focus.gridSession.cancel() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct DisplayGridCard: View {
    let focus: FocusController
    let display: DisplayInfo

    var body: some View {
        Card(padding: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    Text(focus.layout.label(for: display.id)).font(.headline)
                    Spacer()
                    badge
                }
                if let model = focus.gazeModels[display.id], !model.droppedIndices.isEmpty {
                    Text("\(model.droppedIndices.count) of \(model.misses.count) dots ignored as outliers (\(model.error.formatted(.percent.precision(.fractionLength(0)))) without them)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let grid = focus.gazeGrid(for: display.id) {
                    let aspect = display.bounds.width / max(display.bounds.height, 1)
                    GridQualityMap(
                        grid: grid,
                        model: focus.gazeModels[display.id],
                        aspect: aspect,
                        // Fit a 200×110 box so a few screens, even a portrait one, don't outgrow the window.
                        width: min(200, 110 * aspect)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let model = focus.gazeModels[display.id] {
            let kind: Theme.Status = model.gateError <= 0.15 ? .ok : model.gateError <= FocusSettings.maximumWindowError ? .warning : .problem
            Label("\(model.gateError.formatted(.percent.precision(.fractionLength(0)))) error", systemImage: kind.symbol)
                .font(.callout)
                .foregroundStyle(kind.color)
        } else {
            Label("Not usable", systemImage: Theme.Status.problem.symbol)
                .font(.callout)
                .foregroundStyle(Theme.Status.problem.color)
                .help("Move your head more toward each dot and try again.")
        }
    }
}
