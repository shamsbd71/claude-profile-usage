import Foundation

/// What the menu bar app hands to the widget extension: a small JSON file the widget reads.
/// The widget is sandboxed and cannot reach the Keychain, so it never fetches anything itself.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Limit: Codable, Equatable, Sendable {
        public let label: String
        public let percent: Double
        public let severity: String
        public let resetsAt: Date?
    }

    public struct Account: Codable, Equatable, Sendable {
        public let id: String
        /// Email, or the profile name when there is none.
        public let title: String
        public let plan: String
        public let limits: [Limit]
        /// Shown instead of / under the limits when the latest refresh did not succeed.
        public let message: String?
    }

    public let accounts: [Account]
    public let updatedAt: Date

    public init(accounts: [Account], updatedAt: Date) {
        self.accounts = accounts
        self.updatedAt = updatedAt
    }

    public init(accounts: [DisplayAccount], updatedAt: Date) {
        self.accounts = accounts.map { a in
            let limits = (a.snapshot?.limits ?? []).map {
                Limit(label: $0.label, percent: $0.percent, severity: $0.severity.rawValue, resetsAt: $0.resetsAt.map(Self.wholeSeconds))
            }
            let message: String?
            switch a.usage.status {
            case .ok: message = nil
            case .noLogin: message = "No subscription login"
            case .authExpired: message = "Login expired"
            case .rateLimited, .failed: message = a.isStale ? "Stale" : "Unavailable"
            }
            return Account(id: a.id, title: a.usage.profile.email ?? a.id, plan: a.usage.plan,
                           limits: limits, message: message)
        }
        self.updatedAt = Self.wholeSeconds(updatedAt)
    }

    /// Whole seconds survive the JSON round-trip exactly; the widget needs no more precision.
    private static func wholeSeconds(_ d: Date) -> Date {
        Date(timeIntervalSince1970: d.timeIntervalSince1970.rounded(.down))
    }

    public var peakPercent: Double? {
        accounts.flatMap { $0.limits.filter { $0.resetsAt != nil }.map(\.percent) }.max()
    }

    public static func fileURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/ClaudeProfileUsage/widget-snapshot.json")
    }

    /// The real home directory, also from inside the widget's sandbox container.
    public static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        try enc.encode(self).write(to: url, options: .atomic)
    }

    public static func read(from url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(WidgetSnapshot.self, from: data)
    }
}
