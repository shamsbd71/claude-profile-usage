import Foundation
import Testing
@testable import UsageCore

private let prof = Profile(id: "work", configDir: URL(fileURLWithPath: "/tmp/work"), email: "w@example.com",
                           organization: nil, keychainService: "s", isDefault: true)

private func snap(_ t: TimeInterval) -> UsageSnapshot {
    UsageSnapshot(limits: [], fetchedAt: Date(timeIntervalSince1970: t))
}

private func usage(_ status: AccountStatus) -> AccountUsage {
    AccountUsage(profile: prof, plan: "Max 5x", status: status)
}

private func previous(_ s: UsageSnapshot?) -> [DisplayAccount] {
    [DisplayAccount(usage: usage(s.map { .ok($0) } ?? .noLogin), snapshot: s, isStale: false)]
}

@Test func okReplaces() {
    let out = StaleMerge.merge(new: [usage(.ok(snap(2)))], previous: previous(snap(1)))
    #expect(out.first?.snapshot == snap(2) && out.first?.isStale == false)
}

@Test func rateLimitedKeepsLast() {
    let out = StaleMerge.merge(new: [usage(.rateLimited)], previous: previous(snap(1)))
    #expect(out.first?.snapshot == snap(1) && out.first?.isStale == true)
    #expect(out.first?.usage.status == .rateLimited)
}

@Test func failedKeepsLast() {
    let out = StaleMerge.merge(new: [usage(.failed("Offline"))], previous: previous(snap(1)))
    #expect(out.first?.snapshot == snap(1) && out.first?.isStale == true)
}

@Test func noPreviousNoSnapshot() {
    let out = StaleMerge.merge(new: [usage(.failed("Offline"))], previous: [])
    #expect(out.first?.snapshot == nil && out.first?.isStale == false)
}

@Test func authExpiredDropsSnapshot() {
    let out = StaleMerge.merge(new: [usage(.authExpired("x"))], previous: previous(snap(1)))
    #expect(out.first?.snapshot == nil)
}
