import EventKit
import Foundation

protocol CalendarEventManaging: Sendable {
    func createdKeys() async -> Set<String>
    func toggleEvent(for credit: ResetCredit, now: Date) async throws -> Bool
}

actor CalendarService: CalendarEventManaging {
    static let alarmOffsets: [TimeInterval] = [-3_600, -600, -300]

    private enum Keys {
        static let createdResetEvents = "createdResetCalendarEvents"
        static let eventIdentifiers = "createdResetCalendarEventIdentifiers"
    }

    private let eventStore: EKEventStore
    private let defaults: UserDefaults

    init(
        eventStore: EKEventStore = EKEventStore(),
        defaults: UserDefaults = .standard
    ) {
        self.eventStore = eventStore
        self.defaults = defaults
    }

    func createdKeys() -> Set<String> {
        Set(legacyCreatedKeys).union(eventIdentifiers.keys)
    }

    func toggleEvent(
        for credit: ResetCredit,
        now: Date = Date()
    ) async throws -> Bool {
        if createdKeys().contains(credit.id) {
            try await removeEvent(for: credit)
            return false
        }

        try await createEvent(for: credit, now: now)
        return true
    }

    private func createEvent(for credit: ResetCredit, now: Date) async throws {
        guard let expiresAt = credit.expiresAt, expiresAt > now else {
            throw ReminderError.expired
        }
        guard try await requestCreationAccessIfNeeded() else {
            throw ReminderError.calendarDenied
        }
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw ReminderError.calendarUnavailable
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = "Codex reset expiration"
        event.notes = "\(credit.title) — \(ExpiryFormatting.resetDeadline(expiresAt, now: now))"
        event.startDate = expiresAt
        event.endDate = expiresAt.addingTimeInterval(300)
        event.timeZone = .autoupdatingCurrent
        event.calendar = calendar
        for offset in Self.alarmOffsets {
            event.addAlarm(EKAlarm(relativeOffset: offset))
        }

        try eventStore.save(event, span: .thisEvent, commit: true)

        if let identifier = event.eventIdentifier {
            var identifiers = eventIdentifiers
            identifiers[credit.id] = identifier
            defaults.set(identifiers, forKey: Keys.eventIdentifiers)
        } else {
            var keys = Set(legacyCreatedKeys)
            keys.insert(credit.id)
            defaults.set(Array(keys).sorted(), forKey: Keys.createdResetEvents)
        }
    }

    private func removeEvent(for credit: ResetCredit) async throws {
        guard try await requestRemovalAccessIfNeeded() else {
            throw ReminderError.calendarFullAccessDenied
        }

        let storedEvent = eventIdentifiers[credit.id]
            .flatMap { eventStore.event(withIdentifier: $0) }
        let event = storedEvent ?? legacyEvent(for: credit)

        if let event {
            try eventStore.remove(event, span: .thisEvent, commit: true)
        }

        var identifiers = eventIdentifiers
        identifiers.removeValue(forKey: credit.id)
        defaults.set(identifiers, forKey: Keys.eventIdentifiers)

        var legacyKeys = Set(legacyCreatedKeys)
        legacyKeys.remove(credit.id)
        defaults.set(
            Array(legacyKeys).sorted(),
            forKey: Keys.createdResetEvents
        )
    }

    private func legacyEvent(for credit: ResetCredit) -> EKEvent? {
        guard let expiresAt = credit.expiresAt else {
            return nil
        }

        let predicate = eventStore.predicateForEvents(
            withStart: expiresAt.addingTimeInterval(-60),
            end: expiresAt.addingTimeInterval(360),
            calendars: nil
        )
        return eventStore.events(matching: predicate).first { event in
            event.title == "Codex reset expiration" &&
                abs(event.startDate.timeIntervalSince(expiresAt)) < 1
        }
    }

    private func requestCreationAccessIfNeeded() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly, .authorized:
            return true
        case .notDetermined:
            return try await eventStore.requestWriteOnlyAccessToEvents()
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func requestRemovalAccessIfNeeded() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized:
            return true
        case .writeOnly, .notDetermined:
            return try await eventStore.requestFullAccessToEvents()
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private var eventIdentifiers: [String: String] {
        defaults.dictionary(forKey: Keys.eventIdentifiers) as? [String: String]
            ?? [:]
    }

    private var legacyCreatedKeys: [String] {
        defaults.stringArray(forKey: Keys.createdResetEvents) ?? []
    }
}
