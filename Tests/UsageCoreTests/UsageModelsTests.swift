import Foundation
import Testing
@testable import UsageCore

@Test func decodesMaxFixture() throws {
    let s = try UsageDecoder.decode(fixture("usage-max-session-active.json"), fetchedAt: .distantPast)
    #expect(s.limits.map(\.label) == ["Session", "Weekly", "Weekly · Fable"])
    #expect(s.limits.map(\.id) == ["session", "weekly_all", "weekly_scoped:Fable"])
    #expect(s.limits[0].isActive && s.limits[0].severity == .normal && s.limits[0].percent == 4)
    #expect(s.limits[0].resetsAt == UsageDecoder.parseDate("2026-10-24T20:39:59.714429+00:00"))
}

@Test func decodesTeamFixtureNullSession() throws {
    let s = try UsageDecoder.decode(fixture("usage-team-weekly-100.json"), fetchedAt: .distantPast)
    #expect(s.limits[0].kind == "session" && s.limits[0].resetsAt == nil)
    #expect(s.limits[1].percent == 100 && s.limits[1].severity == .critical)
    #expect(s.maxActivePercent == 100)
}

@Test func parsesBothDateShapes() throws {
    let a = try #require(UsageDecoder.parseDate("2026-10-24T20:39:59.714429+00:00"))
    #expect(a.timeIntervalSince1970.rounded(.down) == 1792874399)
    #expect(UsageDecoder.parseDate("2026-11-05T07:59:00+00:00")?.timeIntervalSince1970 == 1793865540)
    #expect(UsageDecoder.parseDate("garbage") == nil)
}

@Test func unknownKindAndLegacyFallback() throws {
    let unk = #"{"limits":[{"kind":"monthly_thing","group":"x","percent":12,"severity":"weird","resets_at":null,"scope":null,"is_active":false}]}"#
    let a = try UsageDecoder.decode(Data(unk.utf8), fetchedAt: .distantPast)
    #expect(a.limits[0].label == "Monthly thing" && a.limits[0].severity == .unknown)
    #expect(a.maxActivePercent == nil)
    let legacy = #"{"five_hour":{"utilization":80.0,"resets_at":"2026-10-24T20:39:59+00:00"},"seven_day":{"utilization":95.0,"resets_at":null}}"#
    let b = try UsageDecoder.decode(Data(legacy.utf8), fetchedAt: .distantPast)
    #expect(b.limits.map(\.label) == ["Session", "Weekly"])
    #expect(b.limits[0].severity == .warning && b.limits[1].severity == .critical)
    #expect(b.limits[0].isActive && !b.limits[1].isActive)
}

@Test func nonJSONThrows() {
    #expect(throws: (any Error).self) { try UsageDecoder.decode(Data("<html>".utf8), fetchedAt: .distantPast) }
}
