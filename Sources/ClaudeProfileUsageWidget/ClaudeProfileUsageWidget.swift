import SwiftUI
import UsageCore
import UsageWidgetViews
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        // The app reloads timelines after every refresh; this is only a fallback.
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func load() -> UsageEntry {
        UsageEntry(date: Date(), snapshot: WidgetSnapshot.read(from: WidgetSnapshot.fileURL(home: WidgetSnapshot.realHome)))
    }
}

@main
struct ClaudeProfileUsageWidgets: WidgetBundle {
    var body: some Widget {
        ClaudeProfileUsageWidget()
    }
}

struct ClaudeProfileUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeProfileUsageWidget", provider: UsageProvider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Profile Usage")
        .description("Session and weekly limits for every claude-profile account.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        WidgetContentView(snapshot: entry.snapshot, family: family)
    }
}
