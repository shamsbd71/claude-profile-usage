import Foundation

/// What the app shows for one account: the latest result plus the last good snapshot.
public struct DisplayAccount: Identifiable, Equatable, Sendable {
    public let usage: AccountUsage
    public let snapshot: UsageSnapshot?
    /// True when `snapshot` is from an earlier refresh because the latest one failed.
    public let isStale: Bool
    public var id: String { usage.id }

    public init(usage: AccountUsage, snapshot: UsageSnapshot?, isStale: Bool) {
        self.usage = usage
        self.snapshot = snapshot
        self.isStale = isStale
    }
}

public enum StaleMerge {
    /// Transient failures (429, network) keep the previous snapshot marked stale;
    /// a lost login or missing credential clears it.
    public static func merge(new: [AccountUsage], previous: [DisplayAccount]) -> [DisplayAccount] {
        let old = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return new.map { u in
            switch u.status {
            case .ok(let s):
                return DisplayAccount(usage: u, snapshot: s, isStale: false)
            case .rateLimited, .failed:
                let last = old[u.id]?.snapshot
                return DisplayAccount(usage: u, snapshot: last, isStale: last != nil)
            case .noLogin, .authExpired:
                return DisplayAccount(usage: u, snapshot: nil, isStale: false)
            }
        }
    }
}
