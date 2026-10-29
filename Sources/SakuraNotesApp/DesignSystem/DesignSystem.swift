import SwiftUI

/// The app's restrained, typography-led design system.
enum DS {

    // MARK: - Spacing

    static let spaceXS: CGFloat = 4
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 24
    static let spaceXXL: CGFloat = 36

    // MARK: - Corner radius

    static let radiusS: CGFloat = 5
    static let radiusM: CGFloat = 8
    static let radiusL: CGFloat = 12

    // MARK: - Accent

    static func accentColor(_ name: String) -> Color {
        switch name {
        case "Sakura Pink": return Color(red: 0.91, green: 0.45, blue: 0.60)
        case "Blue": return Color(red: 0.20, green: 0.48, blue: 0.94)
        case "Purple": return Color(red: 0.60, green: 0.40, blue: 0.90)
        case "Green": return Color(red: 0.20, green: 0.66, blue: 0.42)
        case "Orange": return Color(red: 0.94, green: 0.52, blue: 0.20)
        case "Graphite": return Color(red: 0.42, green: 0.42, blue: 0.46)
        default: return Color.accentColor
        }
    }

    // MARK: - Typography

    static func title(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .semibold, design: .default) }
    static func body(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .regular) }
    static func secondary(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .regular) }
    static func caption(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .regular) }
    static func mono(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .regular, design: .monospaced) }
}

// MARK: - Reusable components

/// A quiet secondary button used in toolbars and panels.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.secondary(12))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusS)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.05))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Sidebar section header.
struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(DS.caption())
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .kerning(0.4)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Image(systemName: actionTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DS.spaceM)
        .padding(.top, DS.spaceL)
        .padding(.bottom, DS.spaceXS)
    }
}

/// Empty / placeholder states with a clear next action.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actions: [(String, () -> Void)] = []

    var body: some View {
        VStack(spacing: DS.spaceM) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.secondary.opacity(0.7))
            Text(title)
                .font(DS.title(15))
            Text(message)
                .font(DS.secondary(12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if !actions.isEmpty {
                HStack(spacing: DS.spaceS) {
                    ForEach(actions.indices, id: \.self) { index in
                        let (label, action) = actions[index]
                        Button(label, action: action)
                            .buttonStyle(QuietButtonStyle())
                    }
                }
                .padding(.top, DS.spaceXS)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A thin separator that matches the app's quiet aesthetic.
struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
    }
}

extension View {
    /// Standard popover presentation with size.
    func sakuraPopover(isPresented: Binding<Bool>, width: CGFloat = 320, @ViewBuilder content: @escaping () -> some View) -> some View {
        popover(isPresented: isPresented, arrowEdge: .bottom) {
            content()
                .frame(width: width)
                .padding(DS.spaceM)
        }
    }
}
