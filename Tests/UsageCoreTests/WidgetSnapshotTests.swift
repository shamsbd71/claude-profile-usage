import Foundation
import Testing
@testable import UsageCore

private let now = Date(timeIntervalSince1970: 1_792_850_000)

private func display(_ id: String, _ status: AccountStatus, snapshot: UsageSnapshot? = nil, stale: Bool = false) -> DisplayAccount {
    let p = Profile(id: id, configDir: URL(fileURLWithPath: "/tmp/\(id)"), email: id == "api-only" ? nil : "\(id)@example.com",
                    organization: nil, keychainService: "s", isDefault: false)
    return DisplayAccount(usage: AccountUsage(profile: p, plan: "Team", status: status), snapshot: snapshot, isStale: stale)
}

@Test func buildsFromDisplayAccounts() throws {
    let snap = try UsageDecoder.decode(fixture("usage-team-weekly-91.json"), fetchedAt: now)
    let w = WidgetSnapshot(accounts: [
        display("client", .ok(snap), snapshot: snap),
        display("api-only", .noLogin),
        display("work", .rateLimited, snapshot: snap, stale: true),
    ], updatedAt: now)
    #expect(w.accounts.map(\.id) == ["client", "api-only", "work"])
    #expect(w.accounts[0].title == "client@example.com" && w.accounts[0].plan == "Team")
    #expect(w.accounts[0].limits.map(\.label) == ["Session", "Weekly"])
    #expect(w.accounts[0].limits[1].percent == 91 && w.accounts[0].limits[1].severity == "critical")
    #expect(w.accounts[0].message == nil)
    #expect(w.accounts[1].title == "api-only" && w.accounts[1].message == "No subscription login")
    #expect(w.accounts[2].limits.count == 2 && w.accounts[2].message == "Stale")
    #expect(w.peakPercent == 91)
}

@Test func roundTripsThroughFile() throws {
    let snap = try UsageDecoder.decode(fixture("usage-max-session-active.json"), fetchedAt: now)
    let w = WidgetSnapshot(accounts: [display("work", .ok(snap), snapshot: snap)], updatedAt: now)
    let url = makeTempDir().appendingPathComponent("nested/widget.json")
    try w.write(to: url)
    #expect(WidgetSnapshot.read(from: url) == w)
    #expect(WidgetSnapshot.read(from: url.appendingPathExtension("missing")) == nil)
}

@Test func fileLocation() {
    let url = WidgetSnapshot.fileURL(home: URL(fileURLWithPath: "/Users/x"))
    #expect(url.path == "/Users/x/Library/Application Support/ClaudeProfileUsage/widget-snapshot.json")
}
