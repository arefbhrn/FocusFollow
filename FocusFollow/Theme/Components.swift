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

/// An icon, a label and a status, optionally with a button to fix a problem.
struct StatusRow: View {
    let symbol: String
    let title: String
    let status: Theme.Status
    let detail: String
    var fixTitle: String?
    var fix: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title)
            Spacer(minLength: Theme.Space.s)
            if let fixTitle, let fix, status != .ok {
                Button(fixTitle, action: fix)
                    .controlSize(.small)
            } else {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: status.symbol)
                        .foregroundStyle(status.color)
                        .accessibilityHidden(true)
                    Text(detail)
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(detail)")
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
    }
}

/// Rounded-rectangle button surface with hover and pressed states, matching `Card`'s shape.
struct TileButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.11 : 0.07))
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.m, style: .continuous))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
