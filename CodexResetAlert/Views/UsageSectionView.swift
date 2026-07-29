import SwiftUI

struct UsageSectionView: View {
    @Bindable var store: ResetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.windows.isEmpty, store.snapshot?.individualLimit == nil {
                Text("Usage windows are unavailable.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            } else {
                ForEach(store.windows) { window in
                    UsageWindowRow(window: window)
                    if window.id != store.windows.last?.id ||
                        store.snapshot?.individualLimit != nil {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }

                if let individualLimit = store.snapshot?.individualLimit {
                    IndividualLimitRow(limit: individualLimit)
                }
            }

            if let message = store.errorMessage {
                ErrorBanner(message: message) {
                    store.dismissError()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
    }
}

private struct UsageWindowRow: View {
    let window: UsageWindow

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Text(window.displayName)
                    .font(.body.weight(.medium))

                Spacer(minLength: 10)

                ProgressView(value: Double(window.remainingPercent), total: 100)
                    .progressViewStyle(.linear)
                    .tint(progressColor)
                    .frame(width: 122)

                Text("\(window.remainingPercent)%")
                    .font(.body.monospacedDigit().weight(.medium))
                    .contentTransition(.numericText())
                    .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: 10) {
                if let resetsAt = window.resetsAt {
                    Text("Resets on \(ExpiryFormatting.usageReset(resetsAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Reset date unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 10)

                Text("remaining")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(window.displayName), \(window.remainingPercent) percent remaining"
        )
    }

    private var progressColor: Color {
        UsageProgressColor.color(for: window.remainingPercent)
    }
}

private struct IndividualLimitRow: View {
    let limit: IndividualLimit

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Text("Monthly")
                    .font(.body.weight(.medium))

                Spacer(minLength: 10)

                ProgressView(value: Double(limit.remainingPercent), total: 100)
                    .progressViewStyle(.linear)
                    .tint(UsageProgressColor.color(for: limit.remainingPercent))
                    .frame(width: 122)

                Text("\(limit.remainingPercent)%")
                    .font(.body.monospacedDigit().weight(.medium))
                    .contentTransition(.numericText())
                    .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: 10) {
                Text("Resets on \(ExpiryFormatting.usageReset(limit.resetsAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 10)

                Text("remaining")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

private enum UsageProgressColor {
    static func color(for remainingPercent: Int) -> Color {
        switch remainingPercent {
        case ..<15:
            return .red
        case ..<40:
            return .orange
        case ..<70:
            return .yellow
        default:
            return .green
        }
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss message")
        }
        .padding(9)
        .background(.orange.opacity(0.10), in: .rect(cornerRadius: 9))
    }
}
