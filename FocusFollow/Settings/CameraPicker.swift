import SwiftUI

struct CameraPicker: View {
    let tracker: HeadTracker

    var body: some View {
        Picker("Camera", selection: selection) {
            ForEach(tracker.cameras) { camera in
                Text(camera.name).tag(camera.id)
            }
        }
        .disabled(tracker.cameras.isEmpty)
    }

    private var selection: Binding<String> {
        Binding(
            get: { tracker.activeCameraID ?? tracker.selectedCameraID ?? "" },
            set: { tracker.selectedCameraID = $0 }
        )
    }
}
