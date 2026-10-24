import Foundation
import Testing
@testable import UsageCore

private let now = Date(timeIntervalSince1970: 1_792_850_000)

private func p(_ id: String, _ email: String?) -> Profile {
    Profile(id: id, configDir: URL(fileURLWithPath: "/tmp/\(id)"), email: email, organization: nil,
            keychainService: "s", isDefault: false)
}

private func rows() throws -> [AccountUsage] {
    let maxSnap = try UsageDecoder.decode(fixture("usage-max-session-active.json"), fetchedAt: now)
    let teamSnap = try UsageDecoder.decode(fixture("usage-team-weekly-100.json"), fetchedAt: now)
    return [
        AccountUsage(profile: p("work", "w@example.com"), plan: "Max 5x", status: .ok(maxSnap)),
        AccountUsage(profile: p("personal", "p@example.com"), plan: "Team", status: .ok(teamSnap)),
        AccountUsage(profile: p("api-only", nil), plan: "—", status: .noLogin),
        AccountUsage(profile: p("client", "r@example.com"), plan: "Team", status: .failed("Offline")),
    ]
}

@Test func tableColumns() throws {
    let rs = try rows()
    let out = TableRenderer.table(rs, now: now, color: false)
    let lines = out.split(separator: "\n").map(String.init)
    #expect(lines.count == 5)
    #expect(lines[0].split(separator: " ").map(String.init) == ["PROFILE", "EMAIL", "PLAN", "SESSION", "WEEKLY", "OTHER"])
    guard case .ok(let maxSnap) = rs[0].status, case .ok(let teamSnap) = rs[1].status else { return }
    #expect(lines[1].contains("4% ↻ " + UsageFormat.countdown(to: maxSnap.limits[0].resetsAt, now: now)))
    #expect(lines[1].contains("Fable 0%"))
    let weeklyCol = lines[0].range(of: "WEEKLY")!.lowerBound.utf16Offset(in: lines[0])
    let sessionCol = lines[0].range(of: "SESSION")!.lowerBound.utf16Offset(in: lines[0])
    let team = lines[2]
    #expect(team.dropFirst(sessionCol).hasPrefix("–"))
    #expect(team.dropFirst(weeklyCol).hasPrefix("100% ↻ " + UsageFormat.countdown(to: teamSnap.limits[1].resetsAt, now: now)))
    #expect(lines[3].contains("no subscription login"))
    #expect(lines[4].contains("error: Offline"))
    #expect(!out.contains("\u{1B}["))
}

@Test func coloredTableHasAnsiOnCritical() throws {
    let out = TableRenderer.table(try rows(), now: now, color: true)
    #expect(out.contains("\u{1B}[31m100%"))
}

@Test func jsonShape() throws {
    let data = try TableRenderer.json(try rows(), now: now)
    let arr = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    #expect(arr.count == 4)
    #expect(arr[0]["profile"] as? String == "work" && arr[0]["email"] as? String == "w@example.com")
    #expect(arr[0]["plan"] as? String == "Max 5x" && arr[0]["status"] as? String == "ok")
    let limits = try #require(arr[0]["limits"] as? [[String: Any]])
    #expect(limits.count == 3 && limits[0]["label"] as? String == "Session" && limits[0]["percent"] as? Double == 4)
    #expect(limits[0]["severity"] as? String == "normal" && (limits[0]["resetsAt"] as? String)?.hasPrefix("2026-10-24T20:39:59") == true)
    #expect(limits[0]["resetsIn"] as? String != nil)
    let teamLimits = try #require(arr[1]["limits"] as? [[String: Any]])
    #expect(teamLimits[0]["resetsAt"] is NSNull)
    #expect(arr[2]["status"] as? String == "no_login" && arr[2]["email"] is NSNull)
    #expect(arr[3]["status"] as? String == "error" && arr[3]["message"] as? String == "Offline")
}

@Test func shortRowsNeverTruncateLeadingCells() {
    let rs = [AccountUsage(profile: p("~/.claude-long-name", "x@example.com"), plan: "Max 5x", status: .authExpired("Login expired"))]
    let out = TableRenderer.table(rs, now: now, color: false)
    #expect(out.contains("~/.claude-long-name  x@example.com"))
}
