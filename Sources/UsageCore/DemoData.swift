import Foundation

/// Fictional accounts for screenshots and trying the UI without real logins
/// (`claude-usage --demo`, or launching the app with `CPU_DEMO=1`).
public enum DemoData {
    public static func accounts(now: Date) -> [DisplayAccount] {
        func limit(_ kind: String, _ label: String, _ percent: Double, resetsIn: TimeInterval?) -> LimitWindow {
            let severity: Severity = percent >= 90 ? .critical : percent >= 75 ? .warning : .normal
            let resetsAt = resetsIn.map { now.addingTimeInterval($0) }
            return LimitWindow(id: kind == "weekly_scoped" ? "\(kind):\(label)" : kind, kind: kind, label: label,
                               percent: percent, severity: severity, resetsAt: resetsAt, isActive: resetsAt != nil)
        }
        func account(_ id: String, _ email: String?, _ plan: String, _ limits: [LimitWindow]?) -> DisplayAccount {
            let profile = Profile(id: id, configDir: URL(fileURLWithPath: "/tmp/demo/\(id)"), email: email,
                                  organization: nil, keychainService: "demo-\(id)", isDefault: id == "work")
            let snapshot = limits.map { UsageSnapshot(limits: $0, fetchedAt: now) }
            let status: AccountStatus = snapshot.map { .ok($0) } ?? .noLogin
            return DisplayAccount(usage: AccountUsage(profile: profile, plan: plan, status: status),
                                  snapshot: snapshot, isStale: false)
        }
        let h: TimeInterval = 3600, d: TimeInterval = 86400
        return [
            account("work", "alex@example.com", "Max 5x", [
                limit("session", "Session", 38, resetsIn: 2 * h + 14 * 60),
                limit("weekly_all", "Weekly", 61, resetsIn: 3 * d + 5 * h),
                limit("weekly_scoped", "Weekly · Opus", 22, resetsIn: 3 * d + 5 * h),
            ]),
            account("personal", "sam@example.com", "Pro", [
                limit("session", "Session", 0, resetsIn: nil),
                limit("weekly_all", "Weekly", 100, resetsIn: 19 * h + 33 * 60),
            ]),
            account("client", "jordan@example.com", "Team", [
                limit("session", "Session", 84, resetsIn: 47 * 60),
                limit("weekly_all", "Weekly", 92, resetsIn: 2 * d + 7 * h),
            ]),
            account("api-only", nil, "—", nil),
        ]
    }
}
