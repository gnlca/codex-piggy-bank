import Foundation

actor CodexAppServerClient {
    private let timeout: Duration

    init(timeout: Duration = .seconds(20)) {
        self.timeout = timeout
    }

    func readSnapshot(
        executableURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> UsageSnapshot {
        let connection = CLIConnection(
            executable: executableURL, arguments: ["app-server", "--stdio"], environment: environment
        )
        return try await withTaskCancellationHandler {
            try connection.start()
            let deadline = Task {
                do { try await Task.sleep(for: timeout) } catch { return }
                connection.stop(timedOut: true)
            }
            defer {
                deadline.cancel()
                connection.stop()
            }
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0"
            try connection.write(CodexRPC.initialize(version: version))
            var accountLabel: String?
            for try await line in connection.lines {
                try Task.checkCancellation()
                guard let data = line.data(using: .utf8),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = (object["id"] as? NSNumber)?.intValue else { continue }
                if let error = RPCErrorPayload.from(object) {
                    throw CodexAppServerError.server(error)
                }
                if id == 0 {
                    try connection.write(CodexRPC.initialized)
                    try connection.write(CodexRPC.accountRead)
                }
                if id == 2 {
                    let result = object["result"] as? [String: Any]
                    accountLabel = (result?["account"] as? [String: Any])?["email"] as? String
                    try connection.write(CodexRPC.rateLimitsRead)
                }
                if id == 1 {
                    let response = try JSONDecoder().decode(RateLimitsEnvelope.self, from: data)
                    var snapshot = response.result.snapshot(fetchedAt: Date())
                    snapshot.accountLabel = accountLabel
                    return snapshot
                }
            }
            try Task.checkCancellation()
            if connection.didTimeOut { throw ProviderConnectionError.timedOut(.codex) }
            throw ProviderConnectionError.unavailable("Codex closed the connection. Check its CLI version and sign-in in Providers.")
        } onCancel: {
            connection.stop()
        }
    }
}

enum CodexAppServerError: LocalizedError, Equatable {
    case server(String)

    var errorDescription: String? {
        switch self {
        case let .server(message): "Codex returned an error: \(message)"
        }
    }
}

private struct RPCErrorPayload {
    static func from(_ object: [String: Any]) -> String? {
        guard let error = object["error"] as? [String: Any] else {
            return nil
        }
        return error["message"] as? String ?? "Unknown error"
    }
}

private struct RateLimitsEnvelope: Decodable {
    let result: RateLimitsResultDTO
}

private struct RateLimitsResultDTO: Decodable {
    let rateLimits: RateLimitSnapshotDTO
    let rateLimitResetCredits: ResetSummaryDTO?

    func snapshot(fetchedAt: Date) -> UsageSnapshot {
        var windows: [UsageWindow] = []

        if let primary = rateLimits.primary {
            windows.append(primary.model(source: .primary))
        }
        if let secondary = rateLimits.secondary {
            windows.append(secondary.model(source: .secondary))
        }

        let resetSummary = rateLimitResetCredits.map { summary in
            ResetSummary(
                availableCount: max(0, summary.availableCount),
                credits: summary.credits?.compactMap(\.model)
            )
        }

        return UsageSnapshot(
            fetchedAt: fetchedAt,
            planType: rateLimits.planType,
            windows: windows,
            individualLimit: rateLimits.individualLimit?.model,
            resetSummary: resetSummary
        )
    }
}

private struct RateLimitSnapshotDTO: Decodable {
    let primary: RateLimitWindowDTO?
    let secondary: RateLimitWindowDTO?
    let individualLimit: IndividualLimitDTO?
    let planType: String?
}

private struct RateLimitWindowDTO: Decodable {
    let usedPercent: Int
    let windowDurationMins: Int?
    let resetsAt: Int64?

    func model(source: UsageWindow.Source) -> UsageWindow {
        UsageWindow(
            usedPercent: usedPercent,
            windowDurationMinutes: windowDurationMins,
            resetsAt: resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            source: source
        )
    }
}

private struct IndividualLimitDTO: Decodable {
    let limit: String
    let used: String
    let remainingPercent: Int
    let resetsAt: Int64

    var model: IndividualLimit {
        IndividualLimit(
            limit: limit,
            used: used,
            remainingPercent: min(100, max(0, remainingPercent)),
            resetsAt: Date(timeIntervalSince1970: TimeInterval(resetsAt))
        )
    }
}

private struct ResetSummaryDTO: Decodable {
    let availableCount: Int
    let credits: [ResetCreditDTO]?
}

private struct ResetCreditDTO: Decodable {
    let resetType: String
    let status: String
    let grantedAt: Int64
    let expiresAt: Int64?
    let title: String?
    let description: String?

    var model: ResetCredit? {
        guard resetType == "codexRateLimits" || resetType == "unknown",
              status == "available" || status == "unknown" else {
            return nil
        }

        return ResetCredit(
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Full reset",
            description: description,
            grantedAt: Date(timeIntervalSince1970: TimeInterval(grantedAt)),
            expiresAt: expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
