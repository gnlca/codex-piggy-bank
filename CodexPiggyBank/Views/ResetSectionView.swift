import SwiftUI

struct ResetSectionView: View {
    @Bindable var store: ResetStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasVisibleCredits {
                creditList
            } else if store.availableResetCount == 0 {
                emptyState
            } else {
                unavailableDetailsState
            }
        }
    }

    private var hasVisibleCredits: Bool {
        !store.resetCredits.isEmpty
    }

    private var creditList: some View {
        VStack(spacing: 8) {
            ForEach(store.resetCredits) { credit in
                ResetCreditRow(store: store, credit: credit)
            }

            if store.missingResetDetailCount > 0 {
                Text(
                    "\(store.missingResetDetailCount) \(store.missingResetDetailCount == 1 ? "reset without details" : "resets without details")"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
            Text("No resets are expiring.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var unavailableDetailsState: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .foregroundStyle(.orange)
            Text("Codex reports the reset count, but not their expiration dates. Update Codex CLI to see the details.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct ResetCreditRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var store: ResetStore
    let credit: ResetCredit

    private var notificationIsActive: Bool {
        store.scheduledNotificationKeys.contains(credit.id)
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
            VStack(alignment: .leading, spacing: 4) {
                Text(credit.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Text(deadlineText)
                    .font(.caption)
                    .foregroundStyle(deadlineColor)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.25),
                        value: deadlineState
                    )
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            reminderActions
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

    @ViewBuilder
    private var reminderActions: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                actionButtons
            }
        } else {
            actionButtons
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
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
            .accessibilityLabel(notificationIsActive ? "Cancel reset alerts" : "Create reset alerts")
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
            .accessibilityLabel(calendarWasCreated ? "Remove from Calendar" : "Add to Calendar")
            .accessibilityValue(calendarWasCreated ? "On" : "Off")
        }
    }

    private var deadlineText: String {
        guard let expiresAt = credit.expiresAt else {
            return "No expiration date"
        }
        return ExpiryFormatting.resetDeadline(expiresAt, now: store.clock)
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
                        .linear(duration: 0.25),
                        value: ringPresentation.progress
                    )
                    .animation(
                        .easeInOut(duration: 0.35),
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
        .frame(width: 38, height: 38)
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
