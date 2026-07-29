import Foundation

actor CodexAppServerClient {
    private let timeout: Duration

    init(timeout: Duration = .seconds(15)) {
        self.timeout = timeout
    }

    func readSnapshot(executableURL: URL) async throws -> UsageSnapshot {
        let session = AppServerSession(
            executableURL: executableURL,
            timeout: timeout
        )
        return try await session.readSnapshot()
    }
}

private final class AppServerSession: @unchecked Sendable {
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private let timeout: Duration

    init(executableURL: URL, timeout: Duration) {
        self.timeout = timeout
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
    }

    func readSnapshot() async throws -> UsageSnapshot {
        try process.run()

        let sessionTimeout = timeout
        let timeoutTask = Task { [weak self, sessionTimeout] in
            try? await Task.sleep(for: sessionTimeout)
            self?.stop()
        }

        defer {
            timeoutTask.cancel()
            stop()
        }

        try write(CodexRPC.initialize(version: appVersion))

        do {
            for try await line in outputPipe.fileHandleForReading.bytes.lines {
                guard let data = line.data(using: .utf8),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = (object["id"] as? NSNumber)?.intValue else {
                    continue
                }

                if id == 0 {
                    if let error = RPCErrorPayload.from(object) {
                        throw CodexAppServerError.server(error)
                    }
                    try write(CodexRPC.initialized)
                    try write(CodexRPC.rateLimitsRead)
                    continue
                }

                if id == 1 {
                    if let error = RPCErrorPayload.from(object) {
                        throw CodexAppServerError.server(error)
                    }
                    let response = try JSONDecoder().decode(RateLimitsEnvelope.self, from: data)
                    return response.result.snapshot(fetchedAt: Date())
                }
            }
        } catch is CancellationError {
            throw CodexAppServerError.timedOut
        } catch let error as CodexAppServerError {
            throw error
        } catch {
            throw CodexAppServerError.invalidResponse(error.localizedDescription)
        }

        let diagnostics = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: diagnostics, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let message, !message.isEmpty {
            throw CodexAppServerError.processFailed(message)
        }
        throw CodexAppServerError.timedOut
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private func write(_ data: Data) throws {
        try inputPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func stop() {
        try? inputPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
    }
}

enum CodexAppServerError: LocalizedError, Equatable {
    case timedOut
    case invalidResponse(String)
    case processFailed(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Codex did not respond within 15 seconds."
        case let .invalidResponse(message):
            return "Codex returned an invalid response: \(message)"
        case let .processFailed(message):
            return "Codex app-server is unavailable: \(message)"
        case let .server(message):
            return "Codex returned an error: \(message)"
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
