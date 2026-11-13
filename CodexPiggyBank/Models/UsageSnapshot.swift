import Foundation

struct UsageSnapshot: Codable, Equatable, Sendable {
    let fetchedAt: Date
    let planType: String?
    let windows: [UsageWindow]
    let individualLimit: IndividualLimit?
    var resetSummary: ResetSummary?
    var accountLabel: String? = nil
    var planTier: String? = nil
    var accountID: String? = nil

    func subscriptionIdentity(for kind: ProviderKind) -> String? {
        if let accountID { return accountID }
        guard kind == .codex, ["plus", "prolite", "pro", "promax", "free", "go"].contains(planType ?? ""),
              let email = accountLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else { return nil }
        return "personal:\(email.lowercased())"
    }

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
                return ($0.grantedAt ?? .distantPast) < ($1.grantedAt ?? .distantPast)
            }
        } ?? []
    }
}

struct UsageWindow: Codable, Equatable, Identifiable, Sendable {
    let usedPercent: Int
    let windowDurationMinutes: Int?
    let resetsAt: Date?
    let source: Source
    var label: String? = nil
    var bucketID: String? = nil

    enum Source: String, Codable, Sendable {
        case primary
        case secondary
        case model
    }

    var id: String {
        bucketID ?? "\(source.rawValue)-\(windowDurationMinutes ?? -1)"
    }

    var remainingPercent: Int {
        min(100, max(0, 100 - usedPercent))
    }

    var isWeekly: Bool {
        windowDurationMinutes == 10_080
    }

    func paceRemainingPercent(now: Date) -> Int? {
        guard let resetsAt, let minutes = windowDurationMinutes, minutes > 0 else { return nil }
        let timeRemaining = resetsAt.timeIntervalSince(now) / (Double(minutes) * 60)
        return Int((min(1, max(0, timeRemaining)) * 100).rounded())
    }

    var displayName: String {
        if let label { return label }
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
        max(0, availableCount - (credits?.reduce(0) { $0 + $1.count } ?? 0))
    }
}

struct ResetCredit: Codable, Equatable, Identifiable, Sendable {
    let title: String
    let description: String?
    let grantedAt: Date?
    let expiresAt: Date?
    var providerCreditID: String? = nil
    var quantity: Int? = nil

    var count: Int { max(0, quantity ?? 1) }

    var id: String {
        if let providerCreditID { return providerCreditID }
        let granted = Int64(grantedAt?.timeIntervalSince1970 ?? 0)
        let expires = expiresAt.map { String(Int64($0.timeIntervalSince1970)) } ?? "never"
        return "\(granted)-\(expires)"
    }

}
