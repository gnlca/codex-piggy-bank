import SwiftUI

struct WeeklyUsageRow: View {
    let window: UsageWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Weekly limit")
                    .font(.body.weight(.medium))

                Spacer(minLength: 10)

                Text("\(window.remainingPercent)% left")
                    .font(.body.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
                    .fixedSize()
            }

            ProgressView(value: Double(window.remainingPercent), total: 100)
                .progressViewStyle(
                    WeeklyUsageProgressStyle(
                        color: UsageProgressColor.color(for: window.remainingPercent)
                    )
                )
                .accessibilityHidden(true)

            Text(resetText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }

    private var resetText: String {
        guard let resetsAt = window.resetsAt else {
            return "Reset date unavailable"
        }
        return "Resets \(ExpiryFormatting.usageReset(resetsAt))"
    }
}

private struct WeeklyUsageProgressStyle: ProgressViewStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.primary.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .overlay {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .white.opacity(0.45), location: 0),
                                            .init(color: .clear, location: 0.45),
                                            .init(color: .black.opacity(0.18), location: 1),
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        }
                        .frame(width: proxy.size.width * (configuration.fractionCompleted ?? 0))
                        .shadow(color: color.opacity(0.32), radius: 4, y: 1)
                }
        }
        .frame(height: 7)
    }
}
