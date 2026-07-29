import Foundation
import UserNotifications

protocol NotificationScheduling: Sendable {
    func scheduledKeys() async -> Set<String>
    func toggle(for credit: ResetCredit, now: Date) async throws -> Bool
    func reconcile(validKeys: Set<String>) async
}

actor NotificationService: NotificationScheduling {
    static let leadTimes: [TimeInterval] = [3_600, 600, 300]

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func scheduledKeys() async -> Set<String> {
        let requests = await center.pendingNotificationRequests()
        return Set(
            requests.compactMap { request in
                Self.creditKey(from: request.identifier)
            }
        )
    }

    func toggle(for credit: ResetCredit, now: Date = Date()) async throws -> Bool {
        let existing = await center.pendingNotificationRequests()
        let existingIdentifiers = existing
            .map(\.identifier)
            .filter { Self.belongsToCredit($0, credit: credit) }

        if !existingIdentifiers.isEmpty {
            center.removePendingNotificationRequests(
                withIdentifiers: existingIdentifiers
            )
            return false
        }

        guard let expiresAt = credit.expiresAt, expiresAt > now else {
            throw ReminderError.expired
        }
        guard try await requestAuthorizationIfNeeded() else {
            throw ReminderError.notificationsDenied
        }

        for reminder in Self.notificationSchedule(
            expiresAt: expiresAt,
            now: now
        ) {
            let content = UNMutableNotificationContent()
            content.title = "Codex reset expires \(reminder.leadTime.label)"
            content.body = "\(credit.title) expires \(ExpiryFormatting.resetDeadline(expiresAt, now: now))."
            content.sound = .default

            let interval = max(1, reminder.fireDate.timeIntervalSince(now))
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: interval,
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "\(credit.notificationIdentifier).\(reminder.leadTime.rawValue)",
                content: content,
                trigger: trigger
            )
            try await center.add(request)
        }
        return true
    }

    func reconcile(validKeys: Set<String>) async {
        let requests = await center.pendingNotificationRequests()
        let obsolete = requests.compactMap { request -> String? in
            guard let key = Self.creditKey(from: request.identifier) else {
                return nil
            }
            return validKeys.contains(key) ? nil : request.identifier
        }
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
        }
    }

    static func notificationDate(expiresAt: Date, now: Date) -> Date {
        max(expiresAt.addingTimeInterval(-300), now.addingTimeInterval(1))
    }

    static func notificationSchedule(
        expiresAt: Date,
        now: Date
    ) -> [NotificationReminder] {
        let futureReminders: [NotificationReminder] =
            NotificationLeadTime.allCases.compactMap {
                leadTime -> NotificationReminder? in
                let fireDate = expiresAt.addingTimeInterval(-leadTime.interval)
                guard fireDate > now else {
                    return nil
                }
                return NotificationReminder(
                    leadTime: leadTime,
                    fireDate: fireDate
                )
            }

        if !futureReminders.isEmpty {
            return futureReminders
        }

        return [
            NotificationReminder(
                leadTime: .fiveMinutes,
                fireDate: now.addingTimeInterval(1)
            ),
        ]
    }

    private static func belongsToCredit(
        _ identifier: String,
        credit: ResetCredit
    ) -> Bool {
        identifier == credit.notificationIdentifier ||
            identifier.hasPrefix("\(credit.notificationIdentifier).")
    }

    private static func creditKey(from identifier: String) -> String? {
        let prefix = "codex-reset-alert."
        guard identifier.hasPrefix(prefix) else {
            return nil
        }

        let remainder = String(identifier.dropFirst(prefix.count))
        guard let separator = remainder.lastIndex(of: ".") else {
            return remainder
        }

        let suffix = String(remainder[remainder.index(after: separator)...])
        guard NotificationLeadTime(rawValue: suffix) != nil else {
            return remainder
        }
        return String(remainder[..<separator])
    }

    private func requestAuthorizationIfNeeded() async throws -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound])
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}

struct NotificationReminder: Equatable, Sendable {
    let leadTime: NotificationLeadTime
    let fireDate: Date
}

enum NotificationLeadTime: String, CaseIterable, Sendable {
    case oneHour = "3600"
    case tenMinutes = "600"
    case fiveMinutes = "300"

    var interval: TimeInterval {
        TimeInterval(rawValue) ?? 0
    }

    var label: String {
        switch self {
        case .oneHour:
            return "in 1 hour"
        case .tenMinutes:
            return "in 10 minutes"
        case .fiveMinutes:
            return "in 5 minutes"
        }
    }
}

enum ReminderError: LocalizedError {
    case expired
    case notificationsDenied
    case calendarDenied
    case calendarFullAccessDenied
    case calendarUnavailable

    var errorDescription: String? {
        switch self {
        case .expired:
            return "This reset has already expired."
        case .notificationsDenied:
            return "Notifications are disabled in System Settings."
        case .calendarDenied:
            return "Write-only Calendar access was not granted."
        case .calendarFullAccessDenied:
            return "Full Calendar access is required only to remove the event you created."
        case .calendarUnavailable:
            return "No default calendar is available."
        }
    }
}
