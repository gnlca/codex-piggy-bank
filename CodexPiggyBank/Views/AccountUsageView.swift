import SwiftUI

struct AccountUsageCard: View {
    let store: ResetStore
    var compact = true

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 12) {
                    heading
                    Spacer(minLength: 0)
                    rings
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    heading
                    rings
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(.primary.opacity(0.055), in: .rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 8) {
            ProviderIcon(profile: store.profile)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.profile.name).font(.system(size: 11, weight: .medium))
                    .lineLimit(compact ? 1 : 2).fixedSize(horizontal: false, vertical: true)
                Text(planDescription).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                if compact, !windows.isEmpty {
                    Text(resetSummary).font(.system(size: 9)).foregroundStyle(.secondary)
                        .monospacedDigit().lineLimit(1)
                        .help(resetHelp)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rings: some View {
        HStack(alignment: .top, spacing: compact ? 6 : 12) {
            if windows.isEmpty {
                UsageRing(remaining: nil, size: compact ? 44 : 64, label: "7d")
            }
            ForEach(windows) { window in
                VStack(alignment: .leading, spacing: 8) {
                    UsageRing(remaining: window.remainingPercent, size: compact ? 44 : 64,
                              isStale: store.isStale, label: window.isWeekly ? "7d" : "5h",
                              paceRemainingPercent: window.paceRemainingPercent(now: store.clock))
                    if !compact {
                        Text("↻ \(resetTime(for: window))")
                            .font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
                            .lineLimit(1)
                            .accessibilityLabel(resetHelp(for: window))
                    }
                }
                .frame(width: compact ? 44 : 68, alignment: .leading)
                .help(ringHelp(for: window))
                .accessibilityElement(children: .combine)
                .accessibilityHint(resetHelp(for: window))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var windows: [UsageWindow] {
        store.overviewWindows
    }

    private var resetSummary: String {
        windows.map { "\($0.isWeekly ? "7d" : "5h") ↻ \(resetTime(for: $0))" }.joined(separator: " · ")
    }

    private var resetHelp: String { windows.map(resetHelp).joined(separator: "\n") }

    private func resetTime(for window: UsageWindow) -> String {
        window.resetsAt.map { ExpiryFormatting.compactDeadline($0, now: store.clock) } ?? "—"
    }

    private func resetHelp(for window: UsageWindow) -> String {
        "\(window.displayName): \(window.resetsAt.map { "resets \(ExpiryFormatting.usageReset($0))" } ?? "reset time unavailable")"
    }

    private func ringHelp(for window: UsageWindow) -> String {
        guard let pace = window.paceRemainingPercent(now: store.clock) else { return resetHelp(for: window) }
        return "\(resetHelp(for: window))\nEven pace: \(pace)% remaining with evenly spread usage."
    }

    private var planDescription: String {
        guard store.snapshot != nil else { return store.isRefreshing ? "Connecting…" : store.connectionLabel }
        return store.isStale ? "\(store.capacity.title) · Out of date" : store.capacity.title
    }
}

struct AccountUsageView: View {
    let store: ResetStore
    var showsAccountHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsAccountHeader {
                HStack(spacing: 10) {
                    ProviderIcon(profile: store.profile)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.profile.name).font(.headline)
                        Text("\(store.capacity.title) · \(store.connectionLabel)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if store.windows.isEmpty {
                Text(store.isRefreshing ? "Checking usage…" : "Usage is unavailable. Open Providers to check this account.")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
            } else {
                ForEach(store.windows) { window in
                    VStack(alignment: .leading, spacing: 8) {
                        UsageLimitView(title: limitTitle(for: window), remainingPercent: window.remainingPercent,
                                       isStale: store.isStale)
                        UsageResetLabel(date: window.resetsAt, now: store.clock)
                    }
                }
            }
            if let limit = store.snapshot?.individualLimit {
                VStack(alignment: .leading, spacing: 4) {
                    UsageLimitView(title: "Monthly limit", remainingPercent: limit.remainingPercent,
                                   isStale: store.isStale)
                    UsageResetLabel(date: limit.resetsAt, now: store.clock)
                }
                .font(.caption)
            }
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func limitTitle(for window: UsageWindow) -> String {
        if window.source == .model { return window.displayName.replacingOccurrences(of: "Weekly · ", with: "") }
        if window.isWeekly { return "Weekly limit" }
        if window.windowDurationMinutes == 300 { return "5h limit" }
        return "\(window.displayName) limit"
    }
}

private struct UsageResetLabel: View {
    let date: Date?
    let now: Date

    var body: some View {
        Text(description)
            .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .help(date.map { ExpiryFormatting.usageReset($0) } ?? "Reset time unavailable")
    }

    private var description: String {
        guard let date else { return "Reset time unavailable" }
        guard date > now else { return "Resetting now" }
        return "Resets in \(ExpiryFormatting.compactDeadline(date, now: now))"
    }
}
