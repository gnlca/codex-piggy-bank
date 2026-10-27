import Foundation

struct ClaudeUsageClient: Sendable {
    var timeout: Duration = .seconds(35)

    func readSnapshot(executableURL: URL, environment: [String: String]) async throws -> UsageSnapshot {
        var arguments = [
            "--print", "--input-format", "stream-json", "--output-format", "stream-json",
            "--verbose", "--no-session-persistence", "--tools", "",
            "--settings", "{\"disableAllHooks\":true}", "--setting-sources", "user",
            "--mcp-config", "{\"mcpServers\":{}}",
        ]
        if !FileManager.default.fileExists(atPath: "/Library/Application Support/ClaudeCode/managed-mcp.json") {
            arguments.append("--strict-mcp-config")
        }
        var environment = environment
        environment["ENABLE_CLAUDEAI_MCP_SERVERS"] = "false"
        environment["CLAUDE_CODE_AUTO_CONNECT_IDE"] = "0"
        environment["CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL"] = "1"
        let connection = CLIConnection(executable: executableURL, arguments: arguments, environment: environment)

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

            try connection.write(Self.request(id: "initialize", subtype: "initialize"))
            var accountLabel: String?
            for try await line in connection.lines {
                try Task.checkCancellation()
                guard let data = line.data(using: .utf8),
                      let message = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      message["type"] as? String == "control_response",
                      let response = message["response"] as? [String: Any],
                      let id = response["request_id"] as? String,
                      id == "initialize" || id == "usage" else { continue }

                guard response["subtype"] as? String == "success",
                      let payload = response["response"] as? [String: Any] else {
                    throw ProviderConnectionError.unavailable(
                        "Claude could not read usage. Sign in to this profile and update Claude Code if needed."
                    )
                }
                if id == "initialize" {
                    accountLabel = (payload["account"] as? [String: Any])?["email"] as? String
                    try connection.write(Self.request(id: "usage", subtype: "get_usage"))
                    continue
                }
                let payloadData = try JSONSerialization.data(withJSONObject: payload)
                var snapshot = try Self.decodeUsage(payloadData)
                snapshot.accountLabel = accountLabel
                if let metadata = ClaudeAccountMetadata.read(environment: environment, email: accountLabel) {
                    snapshot.planTier = metadata.userRateLimitTier ?? metadata.organizationRateLimitTier
                    snapshot.accountID = metadata.identity
                }
                return snapshot
            }
            try Task.checkCancellation()
            if connection.didTimeOut { throw ProviderConnectionError.timedOut(.claude) }
            throw ProviderConnectionError.unavailable("Claude closed the connection. Check its CLI version and sign-in in Providers.")
        } onCancel: {
            connection.stop()
        }
    }

    static func request(id: String, subtype: String) throws -> Data {
        precondition(subtype == "initialize" || subtype == "get_usage")
        var request: [String: Any] = ["subtype": subtype]
        if subtype == "get_usage" { request["skip_behaviors"] = true }
        return try JSONSerialization.data(withJSONObject: [
            "type": "control_request", "request_id": id, "request": request,
        ]) + Data([0x0A])
    }

    static func decodeUsage(_ data: Data, now: Date = Date()) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        guard response.rate_limits_available else {
            throw ProviderConnectionError.unavailable(
                "Claude subscription limits are unavailable for this login. Sign in with a Claude subscription."
            )
        }
        guard let limits = response.rate_limits else {
            throw ProviderConnectionError.unavailable("Claude could not load usage. Try refreshing later.")
        }
        var windows: [UsageWindow] = []
        if let window = limits.five_hour?.model(source: .primary, minutes: 300) { windows.append(window) }
        if let window = limits.seven_day?.model(source: .secondary, minutes: 10_080) { windows.append(window) }
        for scoped in limits.model_scoped ?? [] {
            if var window = scoped.model(source: .model, minutes: 10_080) {
                window.label = "Weekly · \(scoped.display_name ?? "Model")"
                window.bucketID = "model-\(scoped.display_name ?? "unknown")"
                if !windows.contains(where: { $0.id == window.id }) { windows.append(window) }
            }
        }
        guard !windows.isEmpty else { throw ProviderConnectionError.invalidResponse(.claude) }
        return UsageSnapshot(
            fetchedAt: now, planType: response.subscription_type, windows: windows,
            individualLimit: nil, resetSummary: decodeResetCredits(data, now: now)
        )
    }

    static func decodeResetCredits(_ data: Data, now: Date) -> ResetSummary? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = root["rate_limits"] as? [String: Any],
              let block = limits["cedar_ember"] as? [String: Any],
              block["eligible"] as? Bool == true else { return nil }
        let grants = (block["grants"] as? [[String: Any]] ?? []).compactMap { raw -> ResetCredit? in
            guard let data = try? JSONSerialization.data(withJSONObject: raw),
                  let grant = try? JSONDecoder().decode(Grant.self, from: data),
                  grant.id.range(of: "^[a-z0-9_-]{1,40}$", options: .regularExpression) != nil,
                  grant.resets_left >= 0, grant.usable_now == true, grant.paused != true else { return nil }
            var expiresAt: Date?
            if let date = grant.ends_at {
                guard let parsed = claudeDate(date), parsed > now else { return nil }
                expiresAt = parsed
            }
            return ResetCredit(title: "Full reset", description: nil, grantedAt: nil, expiresAt: expiresAt,
                               providerCreditID: "claude-\(grant.id)", quantity: grant.resets_left)
        }
        guard let next = block["next_grant_id"] as? String,
              grants.contains(where: { $0.providerCreditID == "claude-\(next)" }) else {
            return ResetSummary(availableCount: 0, credits: [])
        }
        return ResetSummary(availableCount: grants.reduce(0) { $0 + $1.count }, credits: grants)
    }

    private struct Grant: Decodable {
        let id: String
        let resets_left: Int
        let ends_at: String?
        let paused: Bool?
        let usable_now: Bool?
    }
}

struct ClaudeAccountMetadata: Decodable {
    let emailAddress: String?
    let accountUuid: String?
    let organizationUuid: String?
    let organizationRateLimitTier: String?
    let userRateLimitTier: String?

    var identity: String? {
        guard let accountUuid, let organizationUuid else { return nil }
        return "\(accountUuid):\(organizationUuid)"
    }

    static func read(environment: [String: String], email: String?) -> ClaudeAccountMetadata? {
        let path = environment["CLAUDE_CONFIG_DIR"].map { "\($0)/.claude.json" }
            ?? "\(NSHomeDirectory())/.claude.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath)) else { return nil }
        return decode(data, email: email)
    }

    static func decode(_ data: Data, email: String?) -> ClaudeAccountMetadata? {
        guard let email, let metadata = try? JSONDecoder().decode(Config.self, from: data).oauthAccount,
              metadata.emailAddress?.localizedCaseInsensitiveCompare(email) == .orderedSame else { return nil }
        return metadata
    }

    private struct Config: Decodable {
        let oauthAccount: ClaudeAccountMetadata?
    }
}

private func claudeDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

private struct ClaudeUsageResponse: Decodable {
    let subscription_type: String?
    let rate_limits_available: Bool
    let rate_limits: Limits?

    struct Limits: Decodable {
        let five_hour: Window?
        let seven_day: Window?
        let model_scoped: [Window]?
    }

    struct Window: Decodable {
        let utilization: Double?
        let resets_at: String?
        let display_name: String?

        func model(source: UsageWindow.Source, minutes: Int) -> UsageWindow? {
            guard let utilization, utilization.isFinite else { return nil }
            return UsageWindow(
                usedPercent: Int(min(100, max(0, utilization)).rounded()),
                windowDurationMinutes: minutes, resetsAt: resets_at.flatMap(claudeDate), source: source
            )
        }
    }
}
