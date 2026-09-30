#if DEBUG
import AppKit
import SwiftUI

/// Development aid: renders the app's own windows to PNG files so the UI can be reviewed without screen capture.
/// Run the app with `-snapshotDir /some/folder`; it writes light and dark images of each window and quits.
@MainActor
enum UISnapshot {
    /// Only the command-line argument counts, not a value saved in the app's defaults.
    static var requestedDirectory: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-snapshotDir"), arguments.indices.contains(flag + 1) else { return nil }
        return URL(fileURLWithPath: (arguments[flag + 1] as NSString).standardizingPath, isDirectory: true)
    }

    static func run(appState: AppState, into directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            NSLog("UISnapshot: cannot create %@: %@", directory.path, error.localizedDescription)
            NSApp.terminate(nil)
            return
        }
        let screens: [(String, AnyView)] = [
            ("settings-general", AnyView(SettingsView(tracker: appState.tracker, focus: appState.focus, tab: .general))),
            ("settings-switching", AnyView(SettingsView(tracker: appState.tracker, focus: appState.focus, tab: .switching))),
            ("settings-windows", AnyView(SettingsView(tracker: appState.tracker, focus: appState.focus, tab: .windows))),
            ("settings-displays", AnyView(SettingsView(tracker: appState.tracker, focus: appState.focus, tab: .displays))),
            ("calibration", AnyView(CalibrationView(focus: appState.focus, tracker: appState.tracker))),
            ("debug", AnyView(DebugView(tracker: appState.tracker, focus: appState.focus))),
            ("menu", AnyView(MenuContent(appState: appState))),
        ]
        for (name, view) in screens {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                write(render(view, appearance: appearance), to: directory.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
        NSApp.terminate(nil)
    }

    private static func render(_ view: AnyView, appearance name: NSAppearance.Name) -> NSBitmapImageRep? {
        let appearance = NSAppearance(named: name)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: CGSize(width: max(size.width, 1), height: max(size.height, 1)))
        host.layoutSubtreeIfNeeded()

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width * 2), pixelsHigh: Int(host.bounds.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        rep.size = host.bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance?.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            host.bounds.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    private static func write(_ rep: NSBitmapImageRep?, to url: URL) {
        guard let data = rep?.representation(using: .png, properties: [:]) else { return }
        do {
            try data.write(to: url)
        } catch {
            NSLog("UISnapshot: cannot write %@: %@", url.path, error.localizedDescription)
        }
    }
}
#endif
