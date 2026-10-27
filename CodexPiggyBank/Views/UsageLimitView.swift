import SwiftUI

struct UsageLimitView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let title: String
    let remainingPercent: Int?
    var isStale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.body.weight(.medium))
                Spacer(minLength: 10)
                Text(remainingPercent.map { "\($0)% left" } ?? "—")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .contentTransition(reduceMotion ? .identity : .numericText()).fixedSize()
            }
            ProgressView(value: Double(remainingPercent ?? 0), total: 100)
                .progressViewStyle(UsageLimitProgressStyle(
                    color: remainingPercent.map(UsageProgressColor.color) ?? .secondary
                ))
                .accessibilityHidden(true)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: remainingPercent)
        .opacity(isStale ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(remainingPercent.map { "\(title), \($0) percent remaining\(isStale ? ", out of date" : "")" } ?? "\(title) unavailable")
    }
}

private struct UsageLimitProgressStyle: ProgressViewStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            Capsule().fill(.primary.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule().fill(color)
                        .frame(width: proxy.size.width * (configuration.fractionCompleted ?? 0))
                }
        }
        .frame(height: 7)
    }
}
