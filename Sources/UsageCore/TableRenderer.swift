import Foundation

public enum TableRenderer {
    private struct Cell {
        let text: String
        var severity: Severity? = nil
    }

    public static func table(_ rows: [AccountUsage], now: Date, color: Bool) -> String {
        let header = ["PROFILE", "EMAIL", "PLAN", "SESSION", "WEEKLY", "OTHER"].map { Cell(text: $0) }
        let body = rows.map { cells(for: $0, now: now) }
        let all = [header] + body
        // The last column is never padded; a non-ok row's message also spills over freely.
        let columns = header.count
        var widths = [Int](repeating: 0, count: columns)
        for row in all {
            // A short row's last cell spills past the grid, so it doesn't set a width.
            let measured = row.count == columns ? row[...] : row.dropLast()
            for (i, c) in measured.enumerated() { widths[i] = max(widths[i], c.text.count) }
        }
        return all.map { row in
            row.enumerated().map { i, c in
                let padded = i == row.count - 1 ? c.text : c.text.padding(toLength: widths[i], withPad: " ", startingAt: 0)
                return color ? colorize(padded, c.severity) : padded
            }
            .joined(separator: "  ")
            .replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        }
        .joined(separator: "\n") + "\n"
    }

    private static func cells(for row: AccountUsage, now: Date) -> [Cell] {
        let lead = [Cell(text: row.profile.id), Cell(text: row.profile.email ?? "–"), Cell(text: row.plan)]
        switch row.status {
        case .ok(let snap):
            let session = snap.limits.first { $0.kind == "session" }
            let weekly = snap.limits.first { $0.kind == "weekly_all" }
            let other = snap.limits
                .filter { $0.kind != "session" && $0.kind != "weekly_all" }
                .map { "\(shortLabel($0)) \(UsageFormat.percent($0.percent))" }
                .joined(separator: ", ")
            return lead + [limitCell(session, now: now), limitCell(weekly, now: now), Cell(text: other)]
        case .noLogin: return lead + [Cell(text: "no subscription login")]
        case .authExpired(let msg): return lead + [Cell(text: msg, severity: .warning)]
        case .rateLimited: return lead + [Cell(text: "rate limited — try again shortly", severity: .warning)]
        case .failed(let msg): return lead + [Cell(text: "error: \(msg)", severity: .critical)]
        }
    }

    private static func limitCell(_ w: LimitWindow?, now: Date) -> Cell {
        guard let w, !(w.resetsAt == nil && w.percent == 0) else { return Cell(text: "–") }
        var text = UsageFormat.percent(w.percent)
        if w.resetsAt != nil { text += " ↻ " + UsageFormat.countdown(to: w.resetsAt, now: now) }
        return Cell(text: text, severity: w.severity)
    }

    static func shortLabel(_ w: LimitWindow) -> String {
        w.label.hasPrefix("Weekly · ") ? String(w.label.dropFirst("Weekly · ".count)) : w.label
    }

    private static func colorize(_ s: String, _ severity: Severity?) -> String {
        switch severity {
        case .critical: return "\u{1B}[31m\(s)\u{1B}[0m"
        case .warning: return "\u{1B}[33m\(s)\u{1B}[0m"
        default: return s
        }
    }

    // MARK: JSON

    private struct JSONLimit: Encodable {
        let label: String, kind: String, percent: Double, severity: String
        let resetsAt: String?, resetsIn: String, isActive: Bool

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(label, forKey: .label)
            try c.encode(kind, forKey: .kind)
            try c.encode(percent, forKey: .percent)
            try c.encode(severity, forKey: .severity)
            try c.encode(resetsAt, forKey: .resetsAt) // explicit null
            try c.encode(resetsIn, forKey: .resetsIn)
            try c.encode(isActive, forKey: .isActive)
        }
        enum CodingKeys: String, CodingKey { case label, kind, percent, severity, resetsAt, resetsIn, isActive }
    }

    private struct JSONRow: Encodable {
        let profile: String, email: String?, plan: String, status: String
        let message: String?, limits: [JSONLimit]

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(profile, forKey: .profile)
            try c.encode(email, forKey: .email)
            try c.encode(plan, forKey: .plan)
            try c.encode(status, forKey: .status)
            try c.encodeIfPresent(message, forKey: .message)
            try c.encode(limits, forKey: .limits)
        }
        enum CodingKeys: String, CodingKey { case profile, email, plan, status, message, limits }
    }

    public static func json(_ rows: [AccountUsage], now: Date) throws -> Data {
        let iso = ISO8601DateFormatter()
        let out = rows.map { row -> JSONRow in
            var status = "ok", message: String? = nil, limits: [JSONLimit] = []
            switch row.status {
            case .ok(let snap):
                limits = snap.limits.map {
                    JSONLimit(label: $0.label, kind: $0.kind, percent: $0.percent, severity: $0.severity.rawValue,
                              resetsAt: $0.resetsAt.map(iso.string), resetsIn: UsageFormat.countdown(to: $0.resetsAt, now: now),
                              isActive: $0.isActive)
                }
            case .noLogin: status = "no_login"; message = "No Claude subscription login"
            case .authExpired(let m): status = "auth_expired"; message = m
            case .rateLimited: status = "rate_limited"; message = "Rate limited"
            case .failed(let m): status = "error"; message = m
            }
            return JSONRow(profile: row.profile.id, email: row.profile.email, plan: row.plan,
                           status: status, message: message, limits: limits)
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return try enc.encode(out)
    }
}
