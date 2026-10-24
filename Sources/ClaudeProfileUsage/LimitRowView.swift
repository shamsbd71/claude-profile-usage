import SwiftUI
import UsageCore

struct LimitRowView: View {
    let limit: LimitWindow
    let now: Date

    static let labelWidth: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(limit.label)
                    .lineLimit(1)
                    .frame(width: Self.labelWidth, alignment: .leading)
                UsageBar(percent: limit.percent, color: tint)
                Text(UsageFormat.percent(limit.percent))
                    .monospacedDigit()
                    .foregroundStyle(limit.severity == .critical ? .red : .primary)
                    .frame(width: 40, alignment: .trailing)
            }
            Text(resetText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, Self.labelWidth + 8)
        }
    }

    private var resetText: String {
        guard limit.resetsAt != nil else { return "not started" }
        let clock = UsageFormat.resetClock(limit.resetsAt, now: now)
        return "resets in \(UsageFormat.countdown(to: limit.resetsAt, now: now)) · \(clock)"
    }

    private var tint: Color {
        switch limit.severity {
        case .critical: .red
        case .warning: .orange
        case .normal, .unknown: .accentColor
        }
    }
}

/// A capsule bar that keeps its colour in inactive windows (NSProgressIndicator turns grey).
struct UsageBar: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color).frame(width: geo.size.width * min(max(percent, 0), 100) / 100)
            }
        }
        .frame(height: 6)
    }
}
