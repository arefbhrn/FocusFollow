import Observation
import OSLog
import ServiceManagement

/// Registers the app as a login item. The system owns the real state, so it is re-read rather than cached:
/// the user can also change it in System Settings → General → Login Items.
@MainActor
@Observable
final class LaunchAtLogin {
    private static let logger = Logger(subsystem: "com.arefbhrn.focusfollow", category: "login-item")

    /// Real value is loaded by `refresh()` on appear; reading it here would be a system call on every view rebuild.
    private(set) var status = SMAppService.Status.notRegistered
    private(set) var errorMessage: String?

    var isEnabled: Bool {
        status == .enabled
    }

    /// The user must approve it in System Settings before it takes effect.
    var needsApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.logger.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
