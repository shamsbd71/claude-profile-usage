import AppKit
import SwiftUI
import UsageCore
import UsageWidgetViews
import WidgetKit

/// `CPU_RENDER=<dir>` renders README screenshots from demo data, then quits.
@MainActor
enum ScreenshotRenderer {
    static func renderAll(to dir: URL, store: UsageStore) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let panel = PanelView(store: store).background(Color(nsColor: .windowBackgroundColor))
        write(panel, appearance: .aqua, to: dir.appendingPathComponent("panel-light.png"))
        write(panel, appearance: .darkAqua, to: dir.appendingPathComponent("panel-dark.png"))

        let snapshot = WidgetSnapshot(accounts: store.accounts, updatedAt: store.now)
        let sizes: [(WidgetFamily, CGSize, String)] = [
            (.systemSmall, CGSize(width: 170, height: 170), "widget-small"),
            (.systemMedium, CGSize(width: 364, height: 170), "widget-medium"),
            (.systemLarge, CGSize(width: 364, height: 382), "widget-large"),
        ]
        for (family, size, name) in sizes {
            let widget = WidgetContentView(snapshot: snapshot, family: family)
                .padding(16)
                .frame(width: size.width, height: size.height)
                .clipped()
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(12)
            write(widget, appearance: .aqua, to: dir.appendingPathComponent("\(name).png"))
        }
    }

    private static func write<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
