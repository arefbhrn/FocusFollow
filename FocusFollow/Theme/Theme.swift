import AppKit
import SwiftUI

/// Design tokens shared by every window, so spacing, shape and color stay consistent.
enum Theme {
    /// 4-point spacing scale.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let s: CGFloat = 6
        static let m: CGFloat = 10
        static let l: CGFloat = 14
    }

    /// Indigo to teal, the same as the app icon.
    static let brandGradient = LinearGradient(
        colors: [Color(light: 0x4338CA, dark: 0x6D64E8), Color(light: 0x0E7490, dark: 0x22B8D8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Meaning of a status, always shown with an icon and text too, never by color alone.
    enum Status {
        case ok, warning, problem, neutral

        var color: Color {
            switch self {
            case .ok: .green
            case .warning: .orange
            case .problem: .red
            case .neutral: .secondary
            }
        }

        var symbol: String {
            switch self {
            case .ok: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .problem: "xmark.octagon.fill"
            case .neutral: "minus.circle.fill"
            }
        }
    }
}

extension Color {
    /// A color that switches between two hex values with the system appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
