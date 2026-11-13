import Foundation
import Testing
@testable import TokensPiggyBankCore

struct ClaudeUsageTests {
    @Test func decodesSubscriptionWindowsAndModelLimits() throws {
        let data = Data(#"""
        {"subscription_type":"max","rate_limits_available":true,"rate_limits":{
          "five_hour":{"utilization":31.4,"resets_at":"2026-10-27T18:00:00.123Z"},
          "seven_day":{"utilization":80,"resets_at":"2026-10-30T18:00:00Z"},
          "model_scoped":[{"display_name":"Sonnet","utilization":120,"resets_at":null}]
        }}
        """#.utf8)
        let snapshot = try ClaudeUsageClient.decodeUsage(data)
        #expect(snapshot.planType == "max")
        #expect(snapshot.windows.map(\.remainingPercent) == [69, 20, 0])
        #expect(snapshot.windows[0].resetsAt != nil)
        #expect(snapshot.windows[1].resetsAt != nil)
        #expect(snapshot.windows[2].displayName == "Weekly · Sonnet")
        #expect(Set(snapshot.windows.map(\.id)).count == 3)
        #expect(snapshot.resetSummary == nil)
    }

    @Test func classifiesResetGrantsByKind() throws {
        let data = Data(#"""
        {"rate_limits_available":true,"rate_limits":{
          "seven_day":{"utilization":10},
          "cedar_ember":{"eligible":true,"next_grant_id":"weekly_a","grants":[
            {"id":"weekly_a","resets_left":1,"usable_now":true,"clears":["seven_day"],"ends_at":"2026-12-10T22:00:00Z"},
            {"id":"fable_a","resets_left":1,"usable_now":true,"clears":["seven_day_overage_included"],"gives_back_weekly":true},
            {"id":"fable_b","resets_left":2,"usable_now":true,"gives_back_weekly":true,"type":"weekly"},
            {"id":"session_a","resets_left":1,"usable_now":true,"type":"session"},
            {"id":"full_a","resets_left":1,"usable_now":true,"clears":["five_hour","seven_day"]},
            {"id":"odd","resets_left":1,"usable_now":true,"type":7,"clears":[1]}
          ]}
        }}
        """#.utf8)
        let summary = try #require(try ClaudeUsageClient.decodeUsage(data, now: Date(timeIntervalSince1970: 1_790_000_000)).resetSummary)
        #expect(summary.credits?.map(\.title) == [
            "Weekly reset", "Fable reset", "Fable reset", "5-hour reset", "Full reset", "Weekly reset",
        ])
        #expect(summary.credits?[1].description?.contains("doesn't reset your whole week") == true)
        #expect(summary.availableCount == 7)
    }

    @Test(arguments: [
        #"{"rate_limits_available":false,"rate_limits":null}"#,
        #"{"rate_limits_available":true,"rate_limits":null}"#,
        #"{"rate_limits_available":true,"rate_limits":{}}"#,
    ])
    func unavailableLimitsNeverLookLikeUnusedQuota(response: String) {
        #expect(throws: (any Error).self) { try ClaudeUsageClient.decodeUsage(Data(response.utf8)) }
    }

    @Test func usageRequestNeverSendsAPrompt() throws {
        let data = try ClaudeUsageClient.request(id: "usage", subtype: "get_usage")
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let request = try #require(object["request"] as? [String: Any])
        #expect(object["type"] as? String == "control_request")
        #expect(request["subtype"] as? String == "get_usage")
        #expect(request["skip_behaviors"] as? Bool == true)
        #expect(object["message"] == nil)
    }

    @Test func cachesDoNotCrossAccounts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let work = SnapshotCache(fileURL: directory.appendingPathComponent("work.json"))
        let personal = SnapshotCache(fileURL: directory.appendingPathComponent("personal.json"))
        let snapshot = UsageSnapshot(fetchedAt: Date(timeIntervalSince1970: 100), planType: "max", windows: [],
                                     individualLimit: nil, resetSummary: nil)
        try await work.save(snapshot)
        #expect(await personal.load() == nil)
        #expect(await work.load() == snapshot)
    }
}
