import Foundation

protocol UsageReading: Sendable {
    func readSnapshot(for profile: ProviderProfile) async throws -> UsageSnapshot
}

struct ProviderUsageClient: UsageReading {
    func readSnapshot(for profile: ProviderProfile) async throws -> UsageSnapshot {
        guard let executable = ProviderExecutableLocator.resolve(profile) else {
            throw ProviderConnectionError.executableNotFound(profile.kind)
        }
        switch profile.kind {
        case .codex:
            return try await CodexAppServerClient().readSnapshot(
                executableURL: executable, environment: profile.environment
            )
        case .claude:
            return try await ClaudeUsageClient().readSnapshot(
                executableURL: executable, environment: profile.environment
            )
        }
    }
}

enum ProviderConnectionError: LocalizedError {
    case executableNotFound(ProviderKind)
    case timedOut(ProviderKind)
    case invalidResponse(ProviderKind)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .executableNotFound(kind):
            "\(kind.title) CLI was not found. Set its executable in Providers."
        case let .timedOut(kind):
            "\(kind.title) did not respond in time. Check your connection and try again."
        case let .invalidResponse(kind):
            "\(kind.title) returned an unsupported response. Update its CLI and try again."
        case let .unavailable(message):
            message
        }
    }
}
