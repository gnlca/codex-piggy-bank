import Foundation

struct UsageSnapshot: Codable, Equatable, Sendable {
    let fetchedAt: Date
    let planType: String?
    let windows: [UsageWindow]
    let individualLimit: IndividualLimit?
    let resetSummary: ResetSummary?

    var sortedResetCredits: [ResetCredit] {
        resetSummary?.credits?.sorted {
            switch ($0.expiresAt, $1.expiresAt) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return $0.grantedAt < $1.grantedAt
            }
        } ?? []
    }
}

struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    let usedPercent: Int
    let windowDurationMinutes: Int?
    let resetsAt: Date?
    let source: Source

    enum Source: String, Codable, Sendable {
        case primary
        case secondary
    }

    var id: String {
        "\(source.rawValue)-\(windowDurationMinutes ?? -1)"
    }

    var remainingPercent: Int {
        min(100, max(0, 100 - usedPercent))
    }

    var displayName: String {
        guard let minutes = windowDurationMinutes else {
            return source == .primary ? "Usage" : "Secondary usage"
        }

        switch minutes {
        case 300:
            return "5 hours"
        case 10_080:
            return "Weekly"
        case 40_320...46_080:
            return "Monthly"
        default:
            if minutes.isMultiple(of: 1_440) {
                return "\(minutes / 1_440) days"
            }
            if minutes.isMultiple(of: 60) {
                return "\(minutes / 60) hours"
            }
            return "\(minutes) minutes"
        }
    }
}

struct IndividualLimit: Codable, Equatable, Sendable {
    let limit: String
    let used: String
    let remainingPercent: Int
    let resetsAt: Date
}

struct ResetSummary: Codable, Equatable, Sendable {
    let availableCount: Int
    let credits: [ResetCredit]?

    var missingDetailCount: Int {
        max(0, availableCount - (credits?.count ?? 0))
    }
}

struct ResetCredit: Codable, Equatable, Identifiable, Sendable {
    let title: String
    let description: String?
    let grantedAt: Date
    let expiresAt: Date?

    var id: String {
        let granted = Int64(grantedAt.timeIntervalSince1970)
        let expires = expiresAt.map { String(Int64($0.timeIntervalSince1970)) } ?? "never"
        return "\(granted)-\(expires)"
    }

    var notificationIdentifier: String {
        "codex-piggy-bank.\(id)"
    }
}
