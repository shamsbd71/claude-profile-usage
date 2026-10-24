import Foundation

public enum Severity: String, Sendable {
    case normal, warning, critical, unknown
}

public struct LimitWindow: Identifiable, Equatable, Sendable {
    /// `kind`, or `kind:scopeName` for model-scoped limits.
    public let id: String
    public let kind: String
    public let label: String
    public let percent: Double
    public let severity: Severity
    public let resetsAt: Date?
    public let isActive: Bool
}

public struct UsageSnapshot: Equatable, Sendable {
    public let limits: [LimitWindow]
    public let fetchedAt: Date

    /// Highest percent among windows that have started; nil when none has.
    public var maxActivePercent: Double? {
        limits.filter { $0.resetsAt != nil }.map(\.percent).max()
    }
}

public enum UsageDecoder {
    public static func decode(_ data: Data, fetchedAt: Date) throws -> UsageSnapshot {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CredentialError.malformed
        }
        if let limits = obj["limits"] as? [[String: Any]] {
            return UsageSnapshot(limits: limits.map(window), fetchedAt: fetchedAt)
        }
        let legacy: [(key: String, kind: String, label: String)] = [
            ("five_hour", "session", "Session"),
            ("seven_day", "weekly_all", "Weekly"),
            ("seven_day_opus", "weekly_scoped", "Weekly · Opus"),
            ("seven_day_sonnet", "weekly_scoped", "Weekly · Sonnet"),
        ]
        let windows = legacy.compactMap { entry -> LimitWindow? in
            guard let w = obj[entry.key] as? [String: Any] else { return nil }
            let percent = (w["utilization"] as? NSNumber)?.doubleValue ?? 0
            let resetsAt = (w["resets_at"] as? String).flatMap(parseDate)
            let severity: Severity = percent >= 90 ? .critical : percent >= 75 ? .warning : .normal
            let id = entry.kind == "weekly_scoped" ? "\(entry.kind):\(entry.label.dropFirst("Weekly · ".count))" : entry.kind
            return LimitWindow(id: id, kind: entry.kind, label: entry.label, percent: percent,
                               severity: severity, resetsAt: resetsAt, isActive: resetsAt != nil)
        }
        return UsageSnapshot(limits: windows, fetchedAt: fetchedAt)
    }

    private static func window(_ l: [String: Any]) -> LimitWindow {
        let kind = l["kind"] as? String ?? "unknown"
        let scopeName = ((l["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
        let label: String
        switch kind {
        case "session": label = "Session"
        case "weekly_all": label = "Weekly"
        case "weekly_scoped": label = "Weekly · \(scopeName ?? "scoped")"
        default:
            let words = kind.replacingOccurrences(of: "_", with: " ")
            label = words.prefix(1).uppercased() + words.dropFirst()
        }
        return LimitWindow(
            id: scopeName.map { "\(kind):\($0)" } ?? kind,
            kind: kind,
            label: label,
            percent: (l["percent"] as? NSNumber)?.doubleValue ?? 0,
            severity: Severity(rawValue: l["severity"] as? String ?? "") ?? .unknown,
            resetsAt: (l["resets_at"] as? String).flatMap(parseDate),
            isActive: l["is_active"] as? Bool ?? false
        )
    }

    /// Accepts ISO-8601 with or without fractional seconds (the API sends 6 digits).
    public static func parseDate(_ s: String) -> Date? {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let plain = Date.ISO8601FormatStyle()
        if let d = try? withFraction.parse(s) { return d }
        if let d = try? plain.parse(s) { return d }
        // Trim fractional seconds to milliseconds and retry.
        if let dot = s.firstIndex(of: "."),
           let end = s[dot...].firstIndex(where: { !$0.isNumber && $0 != "." }) {
            let digits = s[s.index(after: dot)..<end].prefix(3)
            let trimmed = s[..<dot] + "." + digits.padding(toLength: 3, withPad: "0", startingAt: 0) + s[end...]
            return try? withFraction.parse(String(trimmed))
        }
        return nil
    }
}
