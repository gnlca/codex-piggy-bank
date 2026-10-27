import Foundation
import Testing
@testable import TokensPiggyBankCore

struct CLIConnectionTests {
    @Test func codexReadsOnlyAccountAndLimitsInTheSelectedHome() async throws {
        let fixture = try TemporaryCLI(script: #"""
        test "$CODEX_HOME" = '/tmp/isolated codex' || exit 2
        while IFS= read -r line; do
          case "$line" in
            *'"method":"initialize"'*) printf '%s\n' '{"id":0,"result":{}}' ;;
            *'rateLimits'*)
              printf '%s\n' '{"id":1,"result":{"rateLimits":{"planType":"pro","primary":{"usedPercent":40,"windowDurationMins":300}},"rateLimitResetCredits":{"availableCount":2,"credits":[]}}}' ;;
            *'account'*) printf '%s\n' '{"id":2,"result":{"account":{"email":"test@example.invalid"}}}' ;;
            *'"method":"initialized"'*) ;;
            *) exit 3 ;;
          esac
        done
        """#)
        defer { fixture.remove() }
        let snapshot = try await CodexAppServerClient(timeout: .seconds(2)).readSnapshot(
            executableURL: fixture.executable, environment: ["CODEX_HOME": "/tmp/isolated codex"]
        )
        #expect(snapshot.accountLabel == "test@example.invalid")
        #expect(snapshot.windows.first?.remainingPercent == 60)
        #expect(snapshot.resetSummary?.availableCount == 2)
    }

    @Test func claudeInitializesAndReadsUsageWithoutAPrompt() async throws {
        let fixture = try TemporaryCLI(script: #"""
        test "$CLAUDE_CONFIG_DIR" = '/tmp/isolated claude' || exit 2
        while IFS= read -r line; do
          case "$line" in
            *'"subtype":"initialize"'*)
              printf '%s\n' '{"type":"control_response","response":{"subtype":"success","request_id":"initialize","response":{"account":{"email":"test@example.invalid"}}}}' ;;
            *'"subtype":"get_usage"'*)
              printf '%s\n' '{"type":"control_response","response":{"subtype":"success","request_id":"usage","response":{"rate_limits_available":true,"subscription_type":"max","rate_limits":{"seven_day":{"utilization":12,"resets_at":null}}}}}' ;;
            *) exit 3 ;;
          esac
        done
        """#)
        defer { fixture.remove() }
        let snapshot = try await ClaudeUsageClient(timeout: .seconds(2)).readSnapshot(
            executableURL: fixture.executable, environment: ["CLAUDE_CONFIG_DIR": "/tmp/isolated claude"]
        )
        #expect(snapshot.accountLabel == "test@example.invalid")
        #expect(snapshot.windows.first?.remainingPercent == 88)
    }

    @Test func unresponsiveProcessIsStoppedAtTheDeadline() async throws {
        let fixture = try TemporaryCLI(script: "exec /bin/sleep 60")
        defer { fixture.remove() }
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: ProviderConnectionError.self) {
            try await ClaudeUsageClient(timeout: .milliseconds(100)).readSnapshot(
                executableURL: fixture.executable, environment: [:]
            )
        }
        #expect(start.duration(to: clock.now) < .seconds(3))
    }

    @Test func cancellationStopsAWaitingProcess() async throws {
        let fixture = try TemporaryCLI(script: "exec /bin/sleep 60")
        defer { fixture.remove() }
        let task = Task {
            try await CodexAppServerClient().readSnapshot(executableURL: fixture.executable)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func legacySnapshotsStillDecode() throws {
        let data = Data(#"""
        {"fetchedAt":"2026-10-27T12:00:00Z","planType":"pro","windows":[
          {"usedPercent":25,"windowDurationMinutes":300,"source":"primary"}
        ],"resetSummary":{"availableCount":0}}
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(UsageSnapshot.self, from: data)
        #expect(snapshot.windows.first?.remainingPercent == 75)
        #expect(snapshot.accountLabel == nil)
    }
}

private struct TemporaryCLI {
    let directory: URL
    let executable: URL

    init(script: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        executable = directory.appendingPathComponent("mock-cli")
        try ("#!/bin/sh\n" + script + "\n").write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
