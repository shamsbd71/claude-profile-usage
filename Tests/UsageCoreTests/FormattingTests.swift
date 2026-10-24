import Foundation
import Testing
@testable import UsageCore

@Test func countdowns() {
    let now = Date(timeIntervalSince1970: 0)
    #expect(UsageFormat.countdown(to: nil, now: now) == "not started")
    #expect(UsageFormat.countdown(to: now.addingTimeInterval(-5), now: now) == "now")
    #expect(UsageFormat.countdown(to: now.addingTimeInterval(42 * 60 + 10), now: now) == "42m")
    #expect(UsageFormat.countdown(to: now.addingTimeInterval(2 * 3600 + 14 * 60), now: now) == "2h 14m")
    #expect(UsageFormat.countdown(to: now.addingTimeInterval(6 * 86400 + 11 * 3600 + 30), now: now) == "6d 11h")
}

@Test func plans() {
    #expect(UsageFormat.planLabel(subscriptionType: "max", rateLimitTier: "default_claude_max_5x") == "Max 5x")
    #expect(UsageFormat.planLabel(subscriptionType: "max", rateLimitTier: "default_claude_max_20x") == "Max 20x")
    #expect(UsageFormat.planLabel(subscriptionType: "team", rateLimitTier: "default_raven") == "Team")
    #expect(UsageFormat.planLabel(subscriptionType: "pro", rateLimitTier: nil) == "Pro")
    #expect(UsageFormat.planLabel(subscriptionType: nil, rateLimitTier: nil) == "—")
    #expect(UsageFormat.percent(91.4) == "91%")
}

@Test func resetClock() {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let now = Date(timeIntervalSince1970: 1792850000)          // 2026-10-24 13:53 UTC
    #expect(UsageFormat.resetClock(nil, now: now, calendar: cal) == "")
    #expect(UsageFormat.resetClock(Date(timeIntervalSince1970: 1792874399), now: now, calendar: cal) == "20:39")
    #expect(UsageFormat.resetClock(Date(timeIntervalSince1970: 1793865540), now: now, calendar: cal) == "Thu 5 Nov 07:59")
}
