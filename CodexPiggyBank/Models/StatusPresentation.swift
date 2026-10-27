import Foundation

struct StatusPresentation: Equatable, Sendable {
    enum State: Sendable {
        case loading
        case usage
        case banked
        case approaching
        case urgent
        case empty
        case stale
    }

    let count: Int?
    let deadline: String
    let state: State

    static let loading = StatusPresentation(count: nil, deadline: "—", state: .loading)

    var symbolName: String {
        switch state {
        case .banked, .empty, .usage:
            return "building.columns.fill"
        case .stale:
            return "exclamationmark.triangle"
        case .loading, .approaching, .urgent:
            return "timer"
        }
    }

    var showsBankSummary: Bool {
        state == .banked || state == .empty || state == .usage
    }

    var leadingText: String {
        state == .usage ? "" : count.map(String.init) ?? "—"
    }
}
