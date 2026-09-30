import Carbon.HIToolbox
import SwiftUI

/// The pause / resume shortcut. Kept in one place so it can become configurable later.
enum HotKeyConfig {
    /// Virtual key code (F).
    static let keyCode = UInt32(kVK_ANSI_F)
    /// Carbon modifier mask (control + option + command).
    static let modifiers = UInt32(controlKey | optionKey | cmdKey)

    // The same shortcut for SwiftUI, only used to show it in the menu.
    static let keyEquivalent = KeyEquivalent("f")
    static let eventModifiers: EventModifiers = [.control, .option, .command]
    static let displayString = "⌃⌥⌘F"
}
