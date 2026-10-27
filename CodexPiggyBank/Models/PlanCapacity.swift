import Foundation

struct PlanCapacity: Equatable, Sendable {
    let title: String

    init(profile: ProviderProfile, snapshot: UsageSnapshot?) {
        let plan = snapshot?.planType?.lowercased() ?? ""
        let tier = snapshot?.planTier?.lowercased() ?? plan
        switch profile.kind {
        case .codex:
            title = switch plan {
            case "plus": "Plus"
            case "prolite": "Pro 100 · 5×"
            case "pro": "Pro 200"
            case "promax": "Pro 500"
            case "self_serve_business_prolite": "Business Premium"
            case "team", "business", "self_serve_business_usage_based": "Business"
            case "free": "Free"
            case "go": "Go"
            case "": "Plan unavailable"
            default: plan.capitalized
            }
        case .claude:
            if ["max", "max5", "max20"].contains(plan), ["default_claude_max_5x", "max5"].contains(tier) {
                title = "Max 5×"
            } else if ["max", "max5", "max20"].contains(plan), ["default_claude_max_20x", "max20"].contains(tier) {
                title = "Max 20×"
            } else {
                title = plan.isEmpty ? "Plan unavailable" : plan.capitalized
            }
        }
    }
}
