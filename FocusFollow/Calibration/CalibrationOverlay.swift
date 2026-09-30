import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class CalibrationOverlayModel {
    var title = ""
    var detail = ""
    var progress = 0.0
}

/// A click-through, translucent panel covering one screen with a "Look here" prompt.
@MainActor
final class CalibrationOverlay {
    let model = CalibrationOverlayModel()
    private var panel: NSPanel?

    func show(on display: DisplayInfo) {
        guard let screen = display.screen else {
            hide()
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: CalibrationOverlayView(model: model))
        return panel
    }
}

private struct CalibrationOverlayView: View {
    let model: CalibrationOverlayModel

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Theme.brandGradient, lineWidth: 10)
                .padding(10)
            VStack(spacing: Theme.Space.m) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Theme.brandGradient)
                Text("Look at this screen")
                    .font(.system(size: 34, weight: .bold))
                Text(model.title).font(.title3)
                Text(model.detail).foregroundStyle(.secondary)
                ProgressView(value: model.progress)
                    .frame(width: 260)
            }
            .padding(Theme.Space.xl + Theme.Space.s)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .ignoresSafeArea()
    }
}
