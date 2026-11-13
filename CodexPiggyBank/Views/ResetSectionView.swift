import SwiftUI

struct BankResetList: View {
    let stores: [ResetStore]
    var showsProvider = true

    var body: some View {
        let bank = BankResets(stores: stores)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Banked resets").font(.system(size: 12, weight: .semibold))
                if bank.count > 0 {
                    Text(bank.count.formatted()).font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.primary.opacity(0.07), in: .capsule)
                }
                Spacer()
                if bank.stores.contains(where: \.isStale) {
                    Text("Last known").font(.caption2).foregroundStyle(.orange)
                }
            }
            ForEach(bank.entries) { entry in
                ResetCreditRow(store: entry.store, credit: entry.credit, showsProvider: showsProvider)
            }
            ForEach(bank.stores.filter { $0.missingResetDetailCount > 0 }, id: \.profile.id) { store in
                HStack(spacing: 8) {
                    if showsProvider { ProviderIcon(profile: store.profile) }
                    Text("\(store.missingResetDetailCount) resets · expiry details unavailable")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            if bank.count == 0 {
                Text(stores.contains(where: \.isRefreshing) ? "Checking reset availability…" : "No banked resets reported.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
            }
        }
    }
}

private struct ResetCreditRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var store: ResetStore
    let credit: ResetCredit
    let showsProvider: Bool

    private var notificationIsActive: Bool {
        store.notificationEnabledKeys.contains(credit.id)
    }

    private var calendarWasCreated: Bool {
        store.createdCalendarKeys.contains(credit.id)
    }

    private var isExpired: Bool {
        guard let expiresAt = credit.expiresAt else {
            return false
        }
        return expiresAt <= store.clock
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if showsProvider {
                    ProviderIcon(profile: store.profile)
                        .alignmentGuide(.firstTextBaseline) { _ in 15 }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(credit.title).font(.callout.weight(.medium)).lineLimit(1)
                            .help(credit.description ?? credit.title)
                        if credit.count > 1 {
                            Text("×\(credit.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }

                    Text(deadlineText)
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(deadlineColor)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: deadlineState)
                        .lineLimit(1)
                        .help(credit.expiresAt.map { ExpiryFormatting.usageReset($0) } ?? "No expiration date")
                }
            }

            Spacer(minLength: 8)

            actionButtons
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityElement(children: .contain)
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button {
                Task { await store.toggleNotification(for: credit) }
            } label: {
                ReminderToggleLabel(
                    inactiveImageName: "NucleoBell",
                    activeImageName: "NucleoBellFilled",
                    isOn: notificationIsActive,
                    tint: .blue,
                    expiresAt: credit.expiresAt,
                    now: store.clock
                )
            }
            .buttonStyle(.plain)
            .disabled(isExpired || credit.expiresAt == nil || store.pendingActionKeys.contains(credit.id))
            .help(notificationIsActive ? "Cancel reset alerts" : "Alert me 1 hour, 10 minutes, and 5 minutes before")
            .accessibilityLabel("\(notificationIsActive ? "Cancel reset alerts" : "Create reset alerts") for \(store.profile.name)")
            .accessibilityValue(notificationIsActive ? "On" : "Off")

            Button {
                Task { await store.toggleCalendarEvent(for: credit) }
            } label: {
                ReminderToggleLabel(
                    inactiveImageName: "NucleoCalendarPlus",
                    activeImageName: "NucleoCalendarCheck",
                    isOn: calendarWasCreated,
                    tint: .green,
                    expiresAt: nil,
                    now: store.clock
                )
            }
            .buttonStyle(.plain)
            .disabled(
                store.pendingActionKeys.contains(credit.id) ||
                    (!calendarWasCreated &&
                        (isExpired || credit.expiresAt == nil))
            )
            .help(calendarWasCreated ? "Remove from Calendar" : "Add to Calendar with 3 alerts")
            .accessibilityLabel("\(calendarWasCreated ? "Remove from Calendar" : "Add to Calendar") for \(store.profile.name)")
            .accessibilityValue(calendarWasCreated ? "On" : "Off")
        }
    }

    private var deadlineText: String {
        guard let expiresAt = credit.expiresAt else {
            return "No expiration date"
        }
        guard expiresAt > store.clock else { return "Expired" }
        return "in \(ExpiryFormatting.compactDeadline(expiresAt, now: store.clock))"
    }

    private var deadlineState: DeadlineState {
        guard let expiresAt = credit.expiresAt else {
            return .normal
        }

        let remaining = expiresAt.timeIntervalSince(store.clock)
        if remaining <= 10 * 60 {
            return .critical
        }
        if remaining <= 3_600 {
            return .warning
        }
        return .normal
    }

    private var deadlineColor: Color {
        switch deadlineState {
        case .normal:
            .secondary
        case .warning:
            CountdownRingPresentation.warningColor
        case .critical:
            .red
        }
    }

    private enum DeadlineState: Equatable {
        case normal
        case warning
        case critical
    }
}

private struct ReminderToggleLabel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let inactiveImageName: String
    let activeImageName: String
    let isOn: Bool
    let tint: Color
    let expiresAt: Date?
    let now: Date

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(0.10))

            Circle()
                .strokeBorder(
                    ringPresentation == nil
                        ? (isOn ? tint : Color.primary.opacity(0.10))
                        : Color.primary.opacity(0.10),
                    lineWidth: 3
                )
                .animation(toggleAnimation, value: isOn)

            if let ringPresentation {
                Circle()
                    .inset(by: 1.5)
                    .trim(from: 0, to: ringPresentation.progress)
                    .stroke(
                        ringPresentation.color,
                        style: StrokeStyle(
                            lineWidth: 3,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(
                        reduceMotion ? nil : .linear(duration: 0.25),
                        value: ringPresentation.progress
                    )
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.35),
                        value: ringPresentation.level
                    )
            }

            ZStack {
                animatedIcon(
                    named: inactiveImageName,
                    isVisible: !isOn
                )

                animatedIcon(
                    named: activeImageName,
                    isVisible: isOn
                )
            }
            .frame(width: 18, height: 18)
            .animation(toggleAnimation, value: isOn)
        }
        .frame(width: 40, height: 40)
        .contentShape(Circle())
        .accessibilityHidden(true)
    }

    private var ringPresentation: CountdownRingPresentation? {
        CountdownRingPresentation(expiresAt: expiresAt, now: now)
    }

    private var toggleAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.15)
            : .spring(
                response: 0.3,
                dampingFraction: 1,
                blendDuration: 0
            )
    }

    private func animatedIcon(
        named imageName: String,
        isVisible: Bool
    ) -> some View {
        Image(imageName)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: 18, height: 18)
            .foregroundStyle(.primary)
            .scaleEffect(
                reduceMotion || isVisible
                    ? 1
                    : 0.25
            )
            .opacity(isVisible ? 1 : 0)
            .blur(
                radius: reduceMotion || isVisible
                    ? 0
                    : 4
            )
    }
}
