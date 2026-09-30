import AppKit

enum SingleInstance {
    /// If another copy of this app started before this one, bring it forward and exit.
    /// Call before creating any state that touches the camera or input.
    /// When two copies launch at the same moment, the earlier one (then the lower pid) survives.
    static func exitIfAnotherInstanceIsRunning() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let me = NSRunningApplication.current
        let older = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != me.processIdentifier && !$0.isTerminated }
            .filter { isEarlier($0, than: me) }
        guard let existing = older.first else { return }
        existing.activate()
        exit(0)
    }

    private static func isEarlier(_ a: NSRunningApplication, than b: NSRunningApplication) -> Bool {
        switch (a.launchDate, b.launchDate) {
        case let (x?, y?) where x != y: return x < y
        default: return a.processIdentifier < b.processIdentifier
        }
    }
}
