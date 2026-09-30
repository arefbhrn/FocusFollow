import Carbon.HIToolbox
import OSLog

/// A system-wide hotkey registered through Carbon. Works without any permission.
@MainActor
final class GlobalHotKey {
    private static let logger = Logger(subsystem: "com.arefbhrn.focusfollow", category: "hotkey")
    /// Four-character code "FFLW".
    private static let signature: OSType = 0x4646_4C57

    /// Read by the C callback, which can't capture. Only touched on the main actor.
    private static var action: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        Self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handlerRef: EventHandlerRef?
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, nil, &handlerRef)
        guard installStatus == noErr else {
            Self.logger.error("InstallEventHandler failed: \(installStatus)")
            return
        }
        self.handlerRef = handlerRef

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if registerStatus == noErr {
            self.hotKeyRef = hotKeyRef
        } else {
            // Typically eventHotKeyExistsErr when another app owns the combination.
            Self.logger.error("RegisterEventHotKey failed: \(registerStatus)")
        }
    }

    fileprivate static func fire() {
        action?()
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        Self.action = nil
    }
}

/// Global function so it is nonisolated and converts to a C function pointer. Hops to the main actor
/// explicitly rather than assuming which thread Carbon calls us on.
private func hotKeyEventHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    Task { @MainActor in
        GlobalHotKey.fire()
    }
    return noErr
}
