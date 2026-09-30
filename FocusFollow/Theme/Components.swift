import SwiftUI

/// A tinted rounded square holding an SF Symbol, like the icons in System Settings.
struct IconBadge: View {
    let symbol: String
    var tint: Color = .accentColor
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// An icon, a label and a status. When something needs fixing and a fix is offered, a button replaces nothing:
/// the status stays visible under the title and the button sits at the end.
struct StatusRow: View {
    let symbol: String
    let title: String
    let status: Theme.Status
    let detail: String
    var fixTitle: String?
    /// What VoiceOver reads for the fix button, since its visible title is short.
    var fixAccessibilityLabel: String?
    var fix: (() -> Void)?

    private var showsFix: Bool {
        fix != nil && fixTitle != nil && (status == .warning || status == .problem)
    }

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            if showsFix {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    statusLabel.font(.caption)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title): \(detail)")
                Spacer(minLength: Theme.Space.s)
                if let fixTitle, let fix {
                    Button(fixTitle, action: fix)
                        .controlSize(.small)
                        .accessibilityLabel(fixAccessibilityLabel ?? fixTitle)
                }
            } else {
                Text(title)
                Spacer(minLength: Theme.Space.s)
                statusLabel.font(.callout)
            }
        }
        .accessibilityElement(children: showsFix ? .contain : .combine)
        .accessibilityLabel(showsFix ? Text(verbatim: "") : Text("\(title): \(detail)"))
    }

    private var statusLabel: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
                .accessibilityHidden(true)
            Text(detail)
                .foregroundStyle(.secondary)
        }
    }
}

/// A status as an icon and text. Only the icon carries the color: orange, green and red text on a light
/// background is hard to read, and the meaning is already in the icon shape and the words.
struct StatusLabel: View {
    let kind: Theme.Status
    let text: String
    var secondary = false

    var body: some View {
        Label {
            Text(text).foregroundStyle(secondary ? .secondary : .primary)
        } icon: {
            Image(systemName: kind.symbol).foregroundStyle(kind.color)
        }
    }
}

/// A grouped surface for related content.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Space.l
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6))
            )
    }
}

/// A square button with an icon above its label, for a row of quick actions.
struct ActionTile: View {
    let symbol: String
    let title: String
    var shortcut: KeyEquivalent?
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            VStack(spacing: Theme.Space.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(TileButtonStyle())
        if let shortcut {
            button.keyboardShortcut(shortcut)
        } else {
            button
        }
    }
}

/// Rounded-rectangle button surface with hover and pressed states, matching `Card`'s shape.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TileSurface(configuration: configuration)
    }

    /// Owns the hover state so it resets when the view goes away, for example when the popover closes under the cursor.
    private struct TileSurface: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.11 : 0.07))
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
                .onHover { hovering = $0 }
                .onDisappear { hovering = false }
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}
