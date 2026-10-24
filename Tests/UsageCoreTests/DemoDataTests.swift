import Foundation
import Testing
@testable import UsageCore

@Test func demoDataIsFakeAndCoversEveryState() {
    let now = Date(timeIntervalSince1970: 1_792_850_000)
    let accounts = DemoData.accounts(now: now)
    #expect(accounts.map(\.id) == ["work", "personal", "client", "api-only"])
    #expect(accounts.compactMap(\.usage.profile.email).allSatisfy { $0.hasSuffix("@example.com") })
    #expect(accounts[3].usage.status == .noLogin && accounts[3].snapshot == nil)
    let severities = Set(accounts.compactMap(\.snapshot).flatMap(\.limits).map(\.severity))
    #expect(severities == [.normal, .warning, .critical])
    #expect(accounts[1].snapshot?.limits.first?.resetsAt == nil)
    #expect(accounts.compactMap(\.snapshot).flatMap(\.limits).compactMap(\.resetsAt).allSatisfy { $0 > now })
}
