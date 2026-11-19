import Foundation
import Testing
@testable import TokensPiggyBankCore

struct AntigravityUsageTests {
    @Test func groupsQuotaBucketsLikeT3Code() throws {
        let requestedAt = try #require(ISO8601DateFormatter().date(from: "2026-11-19T12:52:49Z"))
        let data = Data(#"""
        {"groups":[
          {"displayName":"Gemini Models","buckets":[
            {"bucketId":"gemini-weekly","window":"weekly","resetTime":"2026-11-26T12:12:59Z",
             "description":"You have used some of your weekly limit.","remainingFraction":0.994897},
            {"bucketId":"gemini-5h","window":"5h","resetTime":"2026-11-19T17:12:59Z",
             "description":"You have used some of your 5-hour limit.","remainingFraction":0.98213947}]},
          {"displayName":"Claude and GPT models","buckets":[
            {"bucketId":"3p-weekly","window":"weekly","resetTime":"2026-11-26T12:52:49Z","remainingFraction":1},
            {"bucketId":"3p-5h","window":"5h","resetTime":"2026-11-19T17:52:49Z","remainingFraction":0.5}]},
          {"displayName":"Gemini 4 Argon","buckets":[
            {"bucketId":"gemini-argon-wtu-weekly","window":"weekly","resetTime":"2026-11-26T12:52:49Z","remainingFraction":1},
            {"bucketId":"gemini-off","window":"5h","remainingFraction":1,"disabled":true}]}
        ]}
        """#.utf8)
        let windows = AntigravityUsageClient.windows(fromSummary: data, requestedAt: requestedAt)
        #expect(windows.map(\.id) == ["gemini-weekly", "gemini-5h", "3p-weekly", "3p-5h", "gemini-argon-wtu-weekly"])
        #expect(windows.map(\.source) == [.secondary, .primary, .model, .model, .model])
        #expect(windows.map(\.displayName) == [
            "Gemini · Weekly", "Gemini · 5h", "Claude & GPT · Weekly", "Claude & GPT · 5h", "Gemini 4 Argon · Weekly",
        ])
        #expect(windows.map(\.remainingPercent) == [99, 98, 100, 50, 100])
        #expect(windows[0].resetsAt != nil)
        // An untouched bucket's rolling reset is not a real deadline.
        #expect(windows[2].resetsAt == nil)
        #expect(windows[3].resetsAt != nil)
    }

    @Test func readsTheCLIKeychainLogin() throws {
        let item = #"{"token":{"access_token":"ya29.test","token_type":"Bearer","refresh_token":"r","expiry":"2026-11-19T14:43:15.155945+01:00","expires_in":3599},"auth_method":"consumer","id_token_email":"me@example.com"}"#
        let login = try #require(AntigravityUsageClient.login(
            fromKeychainItem: Data(("go-keyring-base64:" + Data(item.utf8).base64EncodedString()).utf8)
        ))
        #expect(login.accessToken == "ya29.test")
        #expect(login.email == "me@example.com")
        #expect(login.isConsumer)
        let expiry = try #require(login.expiresAt)
        #expect(expiry == ISO8601DateFormatter().date(from: "2026-11-19T13:43:15Z"))
        #expect(login.isFresh(at: expiry.addingTimeInterval(-600)))
        #expect(!login.isFresh(at: expiry.addingTimeInterval(-60)))
        #expect(AntigravityUsageClient.login(fromKeychainItem: Data("go-keyring-base64:%%%".utf8)) == nil)
    }

    @MainActor @Test func importsAndSignsInThroughTheAntigravityCLI() throws {
        let settings = Data(#"{"providerInstances":{"antigravity":{"driver":"antigravity","displayName":"Antigravity","enabled":true}}}"#.utf8)
        let profile = try #require(T3ProviderImporter.profiles(from: settings).first)
        #expect(profile.kind == .antigravity)
        #expect(profile.configurationDirectory.isEmpty)
        #expect(ProviderProfile.new(kind: .antigravity).configurationDirectory.isEmpty)
        let command = ProviderLogin.loginCommand(profile, executable: URL(fileURLWithPath: "/opt/homebrew/bin/agy"))
        #expect(command == "/usr/bin/env -u GEMINI_HOME '/opt/homebrew/bin/agy'")
    }
}
