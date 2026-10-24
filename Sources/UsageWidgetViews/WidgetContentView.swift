import SwiftUI
import UsageCore
import WidgetKit

/// Widget content, shared by the widget extension and the app's screenshot renderer.
public struct WidgetContentView: View {
    let snapshot: WidgetSnapshot?
    let family: WidgetFamily

    public init(snapshot: WidgetSnapshot?, family: WidgetFamily) {
        self.snapshot = snapshot
        self.family = family
    }

    public var body: some View {
        if let snapshot, !snapshot.accounts.isEmpty {
            switch family {
            case .systemSmall: SmallView(snapshot: snapshot)
            case .systemMedium: MediumView(snapshot: snapshot)
            default: ListView(snapshot: snapshot, showsResets: true)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.67percent").font(.title2)
                Text("Open Claude Profile Usage to load data")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Small: one line per account with its fullest limit.
private struct SmallView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Claude", systemImage: "gauge.with.dots.needle.67percent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(snapshot.accounts.filter { !$0.limits.isEmpty }.prefix(4), id: \.id) { account in
                let peak = account.limits.max { $0.percent < $1.percent }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(shortName(account.title)).font(.caption2).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(UsageFormat.percent(peak?.percent ?? 0))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                    }
                    Bar(percent: peak?.percent ?? 0, severity: peak?.severity ?? "normal")
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Medium: one row per account — session and weekly side by side.
private struct MediumView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label("Claude", systemImage: "gauge.with.dots.needle.67percent")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Session").frame(width: 92, alignment: .leading)
                Text("Weekly").frame(width: 92, alignment: .leading)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            ForEach(snapshot.accounts.prefix(4), id: \.id) { account in
                HStack(spacing: 8) {
                    Text(shortName(account.title))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if account.limits.isEmpty {
                        Text(account.message ?? "—")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .frame(width: 192, alignment: .leading)
                    } else {
                        cell(account.limits.first { $0.label == "Session" })
                        cell(account.limits.first { $0.label == "Weekly" })
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func cell(_ limit: WidgetSnapshot.Limit?) -> some View {
        HStack(spacing: 4) {
            Bar(percent: limit?.percent ?? 0, severity: limit?.severity ?? "normal")
            Text(limit.map { UsageFormat.percent($0.percent) } ?? "—")
                .font(.caption2).monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
        .frame(width: 92)
    }
}

/// Large: per account, its session and weekly bars with reset countdowns.
private struct ListView: View {
    let snapshot: WidgetSnapshot
    let showsResets: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: showsResets ? 10 : 6) {
            ForEach(snapshot.accounts.prefix(showsResets ? 6 : 4), id: \.id) { account in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(account.title).font(.caption.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 2)
                        if let message = account.message {
                            Text(message).font(.caption2).foregroundStyle(.orange)
                        } else {
                            Text(account.plan).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(account.limits.prefix(2), id: \.label) { limit in
                        HStack(spacing: 6) {
                            Text(limit.label).font(.caption2).frame(width: 46, alignment: .leading)
                            Bar(percent: limit.percent, severity: limit.severity)
                            Text(UsageFormat.percent(limit.percent))
                                .font(.caption2).monospacedDigit()
                                .frame(width: 32, alignment: .trailing)
                            if showsResets {
                                Text(limit.resetsAt == nil ? "—" : UsageFormat.countdown(to: limit.resetsAt, now: Date()))
                                .font(.caption2).foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Text("Updated \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct Bar: View {
    let percent: Double
    let severity: String

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color).frame(width: geo.size.width * min(max(percent, 0), 100) / 100)
            }
        }
        .frame(height: 5)
    }

    private var color: Color {
        switch severity {
        case "critical": .red
        case "warning": .orange
        default: .accentColor
        }
    }
}

private func shortName(_ title: String) -> String {
    title.split(separator: "@").first.map(String.init) ?? title
}
