import AppKit
import OSLog

/// Reasons the system itself wants FocusFollow to stand down.
enum SystemSuspension: Sendable, Hashable, CaseIterable {
    case sleeping
    case displayAsleep
    case screenLocked
    case screenSaver

    var label: String {
        switch self {
        case .sleeping: "system asleep"
        case .displayAsleep: "display asleep"
        case .screenLocked: "screen locked"
        case .screenSaver: "screen saver"
        }
    }
}

/// Watches sleep, display sleep, screen lock and screen saver, and reports which are currently active.
@MainActor
final class SystemStateMonitor {
    private static let logger = Logger(subsystem: "com.arefbhrn.focusfollow", category: "system")

    private(set) var active: Set<SystemSuspension> = []
    /// Called whenever `active` changes.
    var onChange: @MainActor (Set<SystemSuspension>) -> Void = { _ in }

    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.willSleepNotification, on: workspace, set: .sleeping)
        observe(NSWorkspace.didWakeNotification, on: workspace, clear: .sleeping)
        observe(NSWorkspace.screensDidSleepNotification, on: workspace, set: .displayAsleep)
        observe(NSWorkspace.screensDidWakeNotification, on: workspace, clear: .displayAsleep)

        // These are undocumented but long-standing; there is no public API for lock / screen saver state.
        let distributed = DistributedNotificationCenter.default()
        observe(Notification.Name("com.apple.screenIsLocked"), on: distributed, set: .screenLocked)
        observe(Notification.Name("com.apple.screenIsUnlocked"), on: distributed, clear: .screenLocked)
        observe(Notification.Name("com.apple.screensaver.didstart"), on: distributed, set: .screenSaver)
        observe(Notification.Name("com.apple.screensaver.didstop"), on: distributed, clear: .screenSaver)
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter, set reason: SystemSuspension) {
        add(name, on: center) { $0.insert(reason) }
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter, clear reason: SystemSuspension) {
        add(name, on: center) { $0.remove(reason) }
    }

    private func add(
        _ name: Notification.Name,
        on center: NotificationCenter,
        update: @escaping @Sendable (inout Set<SystemSuspension>) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.apply(update)
            }
        }
        observers.append((center, token))
    }

    private func apply(_ update: (inout Set<SystemSuspension>) -> Void) {
        var next = active
        update(&next)
        guard next != active else { return }
        active = next
        Self.logger.info("System suspensions: \(next.map(\.label).sorted().joined(separator: ", "), privacy: .public)")
        onChange(next)
    }
}
