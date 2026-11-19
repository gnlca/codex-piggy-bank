import Foundation

/// Reads Antigravity quotas as T3 Code does, with the Google sign-in the Antigravity CLI keeps in the Keychain.
/// Antigravity reports no banked resets.
struct AntigravityUsageClient: Sendable {
    var timeout: TimeInterval = 10

    private static let dailyHost = "https://daily-cloudcode-pa.googleapis.com"
    private static let prodHost = "https://cloudcode-pa.googleapis.com"
    // T3 Code's quota probe identity; older identities omit the Gemini buckets.
    private static let userAgent = "antigravity/hub/2.24.0 (aidev_client; os_type=darwin; arch=\(architecture); cl=963137146)"

    func readSnapshot(executableURL: URL, environment: [String: String], now: Date = Date()) async throws -> UsageSnapshot {
        var login = await Self.keychainLogin()
        if login?.isFresh(at: now) != true {
            // The CLI refreshes an expiring sign-in and saves it back before listing models.
            _ = await ProcessRunner.output(executableURL, ["models"], environment: environment, timeout: 30)
            login = await Self.keychainLogin()
        }
        guard let login, login.isFresh(at: Date()) else {
            throw ProviderConnectionError.unavailable("Sign in to Antigravity with Google to see its limits.")
        }
        // Consumer accounts are metered on the daily host and business accounts on prod; the metered reading wins.
        let hosts = login.isConsumer ? [Self.dailyHost, Self.prodHost] : [Self.prodHost, Self.dailyHost]
        var responses: [[UsageWindow]] = []
        await withTaskGroup(of: (Int, [UsageWindow]).self) { group in
            for (index, host) in hosts.enumerated() {
                group.addTask { (index, await quotaWindows(host: host, token: login.accessToken)) }
            }
            var ordered = Array(repeating: [UsageWindow](), count: hosts.count)
            for await (index, windows) in group { ordered[index] = windows }
            responses = ordered
        }
        var windows: [UsageWindow] = []
        for window in responses.flatMap({ $0 }) where !windows.contains(where: { $0.id == window.id }) {
            windows.append(window)
        }
        guard !windows.isEmpty else {
            throw ProviderConnectionError.unavailable("Antigravity did not return usable quota information.")
        }
        return UsageSnapshot(fetchedAt: now, planType: nil, windows: windows, individualLimit: nil, resetSummary: nil,
                             accountLabel: login.email, accountID: login.email.map { "google:\($0.lowercased())" })
    }

    private func quotaWindows(host: String, token: String) async -> [UsageWindow] {
        guard let url = URL(string: "\(host)/v1internal:retrieveUserQuotaSummary") else { return [] }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let requestedAt = Date()
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return Self.windows(fromSummary: data, requestedAt: requestedAt)
    }

    /// Windows from a `retrieveUserQuotaSummary` answer, following T3 Code's grouping.
    static func windows(fromSummary data: Data, requestedAt: Date) -> [UsageWindow] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let groups = root["groups"] as? [[String: Any]] ?? []
        let grouped = groups.contains { !($0["buckets"] as? [Any] ?? []).isEmpty }
            ? groups : [["buckets": root["buckets"] ?? []]]
        var windows: [UsageWindow] = []
        for group in grouped {
            let groupName = (group["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            for bucket in group["buckets"] as? [[String: Any]] ?? [] {
                guard bucket["disabled"] as? Bool != true,
                      let id = bucket["bucketId"] as? String, !id.isEmpty,
                      let remaining = (bucket["remainingFraction"] as? NSNumber)?.doubleValue, remaining.isFinite,
                      !windows.contains(where: { $0.id == id }) else { continue }
                let family = id.hasPrefix("gemini-argon-") ? groupName.nonEmpty ?? "Gemini Argon"
                    : id.hasPrefix("gemini-carbon-") ? groupName.nonEmpty ?? "Gemini Carbon"
                    : id.hasPrefix("gemini-") ? "Gemini"
                    : id.hasPrefix("3p-") ? "Claude & GPT"
                    : groupName.nonEmpty ?? id
                let period = bucket["window"] as? String
                let minutes = period == "weekly" ? 10_080 : period == "5h" ? 300 : nil
                var resetsAt = (bucket["resetTime"] as? String).flatMap(googleDate)
                // Untouched buckets report a rolling reset one full window away.
                if remaining == 1, bucket["description"] == nil, let minutes, let reset = resetsAt,
                   abs(reset.timeIntervalSince(requestedAt) - Double(minutes) * 60) <= 60 {
                    resetsAt = nil
                }
                let main = family == "Gemini" && minutes != nil
                let periodName = minutes == 10_080 ? "Weekly" : minutes == 300 ? "5h"
                    : (bucket["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Quota"
                windows.append(UsageWindow(
                    usedPercent: Int(((1 - min(1, max(0, remaining))) * 100).rounded()),
                    windowDurationMinutes: minutes, resetsAt: resetsAt,
                    source: main ? (minutes == 300 ? .primary : .secondary) : .model,
                    label: "\(family) · \(periodName)", bucketID: id
                ))
            }
        }
        return windows
    }

    struct Login: Sendable {
        let accessToken: String
        let expiresAt: Date?
        let email: String?
        let isConsumer: Bool

        func isFresh(at date: Date) -> Bool { expiresAt.map { $0.timeIntervalSince(date) > 120 } ?? true }
    }

    /// Decodes the go-keyring item Antigravity saves under service `gemini`, account `antigravity`.
    static func login(fromKeychainItem data: Data) -> Login? {
        var text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("go-keyring-base64:") {
            guard let decoded = Data(base64Encoded: String(text.dropFirst("go-keyring-base64:".count))) else { return nil }
            text = String(decoding: decoded, as: UTF8.self)
        } else if text.hasPrefix("go-keyring-encoded:") {
            let hex = Array(text.dropFirst("go-keyring-encoded:".count))
            guard hex.count.isMultiple(of: 2) else { return nil }
            let bytes = stride(from: 0, to: hex.count, by: 2).compactMap { UInt8(String(hex[$0...$0 + 1]), radix: 16) }
            guard bytes.count * 2 == hex.count else { return nil }
            text = String(decoding: bytes, as: UTF8.self)
        }
        guard let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let token = root["token"] as? [String: Any],
              let accessToken = (token["access_token"] as? String)?.nonEmpty else { return nil }
        return Login(accessToken: accessToken, expiresAt: (token["expiry"] as? String).flatMap(googleDate),
                     email: (root["id_token_email"] as? String)?.nonEmpty,
                     isConsumer: (root["auth_method"] as? String ?? "consumer") == "consumer")
    }

    private static func keychainLogin() async -> Login? {
        await ProcessRunner.keychainPassword(service: "gemini", account: "antigravity").flatMap(login(fromKeychainItem:))
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x64"
        #endif
    }
}

/// Accepts Go's RFC 3339 timestamps, whose fractional seconds may exceed what ISO8601DateFormatter parses.
private func googleDate(_ value: String) -> Date? {
    let trimmed = value.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: trimmed)
}

private extension Optional where Wrapped == String {
    var nonEmpty: String? { self?.nonEmpty }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
