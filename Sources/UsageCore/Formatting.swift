import Foundation

public enum UsageFormat {
    public static func countdown(to date: Date?, now: Date) -> String {
        guard let date else { return "not started" }
        let total = Int(date.timeIntervalSince(now))
        guard total > 0 else { return "now" }
        let days = total / 86400, hours = total % 86400 / 3600, minutes = total % 3600 / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }

    /// "HH:mm" when the reset is today, otherwise "EEE d MMM HH:mm".
    public static func resetClock(_ date: Date?, now: Date, calendar: Calendar = .current) -> String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "HH:mm" : "EEE d MMM HH:mm"
        return f.string(from: date)
    }

    public static func planLabel(subscriptionType: String?, rateLimitTier: String?) -> String {
        guard let type = subscriptionType, !type.isEmpty else { return "—" }
        var label = type.prefix(1).uppercased() + type.dropFirst()
        if let tier = rateLimitTier,
           let range = tier.range(of: #"\d+x$"#, options: .regularExpression) {
            label += " " + tier[range]
        }
        return label
    }

    public static func percent(_ p: Double) -> String {
        "\(Int(p.rounded()))%"
    }
}
