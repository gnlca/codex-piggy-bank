import SwiftUI

struct ProviderMark: View {
    let kind: ProviderKind

    var body: some View {
        Image(kind == .codex ? "CodexMark" : "ClaudeMark")
            .resizable().renderingMode(kind == .codex ? .template : .original)
            .scaledToFit().accessibilityLabel(kind.title)
    }
}

struct ProviderIcon: View {
    let profile: ProviderProfile
    var size: CGFloat = 22

    var body: some View {
        ProviderMark(kind: profile.kind)
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if let initials = profile.initials {
                    Text(initials)
                        .font(.system(size: max(7, size * 0.3), weight: .bold, design: .rounded))
                        .fixedSize()
                        .foregroundStyle(badgeColor.map { $0.isLight ? Color.black : Color.white } ?? .primary)
                        .padding(.horizontal, 3).frame(height: max(12, size * 0.55))
                        .background(badgeColor?.color ?? Color(nsColor: .controlBackgroundColor), in: .capsule)
                        .overlay { Capsule().strokeBorder(.background.opacity(0.7), lineWidth: 1) }
                        .offset(x: size * 0.22, y: size * 0.2)
                }
            }
            .padding(.trailing, size * 0.22)
            .padding(.bottom, size * 0.2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(profile.name), \(profile.kind.title)")
            .help(profile.name)
    }

    private var badgeColor: BadgeColor? { profile.accentHex.flatMap(BadgeColor.init) }
}

struct BadgeColor {
    let color: Color
    let isLight: Bool

    init?(_ hex: String) {
        let hex = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        let red = Double((value >> 16) & 255) / 255
        let green = Double((value >> 8) & 255) / 255
        let blue = Double(value & 255) / 255
        color = Color(red: red, green: green, blue: blue)
        let linear = [red, green, blue].map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        isLight = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2] > 0.179
    }
}
