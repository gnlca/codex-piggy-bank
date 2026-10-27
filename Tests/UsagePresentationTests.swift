import Foundation
import Testing
@testable import TokensPiggyBankCore

struct UsagePresentationTests {
    private let now = Date(timeIntervalSince1970: 1_793_100_000)

    @Test func deadlinesStayRelativeBeyondTwoDays() {
        let cases: [(TimeInterval, String)] = [
            (-1, "now"), (0, "now"), (1, "1s"), (61, "1m 1s"),
            (3_600, "1h"), (3_660, "1h 1m"), (86_400, "1d"),
            (172_800, "2d"), (183_600, "2d 3h"), (432_000, "5d"),
            (442_800, "5d 3h"), (2_689_200, "31d 3h"),
        ]
        for (interval, expected) in cases {
            #expect(ExpiryFormatting.compactDeadline(now.addingTimeInterval(interval), now: now) == expected)
        }
    }

    @Test func evenPaceTracksTimeRemainingInEachWindow() {
        let cases: [(minutes: Int, timeLeft: TimeInterval, expected: Int)] = [
            (300, 18_000, 100), (300, 9_000, 50), (300, 180, 1),
            (10_080, 604_800, 100), (10_080, 302_400, 50), (10_080, 442_800, 73),
            (300, 0, 0), (300, -60, 0), (300, 36_000, 100),
        ]
        for (minutes, timeLeft, expected) in cases {
            for used in [0, 50, 100] {
                let window = UsageWindow(usedPercent: used, windowDurationMinutes: minutes,
                                         resetsAt: now.addingTimeInterval(timeLeft), source: .primary)
                #expect(window.paceRemainingPercent(now: now) == expected)
            }
        }
    }

    @Test func evenPaceRequiresAResetTimeAndPositiveDuration() {
        let missingReset = UsageWindow(usedPercent: 20, windowDurationMinutes: 300, resetsAt: nil, source: .primary)
        #expect(missingReset.paceRemainingPercent(now: now) == nil)
        for minutes: Int? in [nil, 0, -300] {
            let window = UsageWindow(usedPercent: 20, windowDurationMinutes: minutes,
                                     resetsAt: now.addingTimeInterval(3_600), source: .primary)
            #expect(window.paceRemainingPercent(now: now) == nil)
        }
    }
}
