import AppKit
import CoreGraphics

struct DisplayInfo: Sendable, Equatable, Identifiable {
    /// Stable across launches: vendor / model / serial plus position in the arrangement.
    let id: String
    let displayID: CGDirectDisplayID
    let name: String
    /// Global CoreGraphics coordinates (origin top-left of the primary display).
    /// Accessibility and `CGWindowList` use the same space, as does `CGWarpMouseCursorPosition`.
    let bounds: CGRect
}

/// The set of connected displays at one moment.
struct DisplayLayout: Sendable, Equatable {
    /// Ordered left to right, then top to bottom.
    var displays: [DisplayInfo]

    /// Identifies this arrangement, so calibration can be saved per setup.
    var key: String {
        displays.map(\.id).sorted().joined(separator: "|")
    }

    @MainActor
    static func current() -> DisplayLayout {
        let infos = NSScreen.screens.compactMap { screen -> DisplayInfo? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let bounds = CGDisplayBounds(displayID)
            let hardware = "\(CGDisplayVendorNumber(displayID))-\(CGDisplayModelNumber(displayID))-\(CGDisplaySerialNumber(displayID))"
            let geometry = "\(Int(bounds.minX)),\(Int(bounds.minY)),\(Int(bounds.width))x\(Int(bounds.height))"
            return DisplayInfo(
                id: "\(hardware)@\(geometry)",
                displayID: displayID,
                name: screen.localizedName,
                bounds: bounds
            )
        }
        let sorted = infos.sorted {
            $0.bounds.minX != $1.bounds.minX ? $0.bounds.minX < $1.bounds.minX : $0.bounds.minY < $1.bounds.minY
        }
        return DisplayLayout(displays: sorted)
    }

    func display(withID id: String) -> DisplayInfo? {
        displays.first { $0.id == id }
    }

    /// `point` is in global CoreGraphics coordinates.
    func display(containing point: CGPoint) -> DisplayInfo? {
        displays.first { $0.bounds.contains(point) }
    }

    /// Human-readable name such as "Display 2 (LG UltraFine)".
    func label(for id: String) -> String {
        guard let index = displays.firstIndex(where: { $0.id == id }) else { return "Unknown display" }
        return "Display \(index + 1) (\(displays[index].name))"
    }
}

extension DisplayInfo {
    /// The `NSScreen` for this display, for AppKit windows (bottom-left origin coordinates).
    @MainActor
    var screen: NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }
    }
}
