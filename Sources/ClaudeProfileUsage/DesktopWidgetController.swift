import AppKit
import Combine
import SwiftUI
import UsageCore
import UsageWidgetViews
import WidgetKit

/// A widget that lives on the desktop: a borderless panel at desktop-icon level, so it sits on the
/// wallpaper below normal windows on every Space. Unlike a WidgetKit widget it needs no developer
/// certificate, and it updates live from the app's store.
@MainActor
final class DesktopWidgetController {
    private let store: UsageStore
    private var panel: NSPanel?
    private var host: NSHostingView<DesktopWidgetView>?
    private var cancellables: Set<AnyCancellable> = []

    init(store: UsageStore) {
        self.store = store
        store.$desktopWidgetEnabled.removeDuplicates()
            .combineLatest(store.$desktopWidgetSize.removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled, size in self?.apply(enabled: enabled, size: size) }
            .store(in: &cancellables)
    }

    private func apply(enabled: Bool, size: DesktopWidgetSize) {
        guard enabled else {
            panel?.orderOut(nil)
            return
        }
        let panel = self.panel ?? makePanel()
        let view = DesktopWidgetView(store: store, size: size)
        if let host {
            host.rootView = view
        } else {
            let host = NSHostingView(rootView: view)
            panel.contentView = host
            self.host = host
        }
        resize(panel, to: size.points)
        panel.orderFrontRegardless()
    }

    /// Resizes keeping the top-left corner fixed (AppKit keeps the bottom-left), then keeps the
    /// whole widget on a connected screen — a borderless window is never constrained by AppKit.
    private func resize(_ panel: NSPanel, to size: CGSize) {
        var frame = NSRect(x: panel.frame.minX, y: panel.frame.maxY - size.height, width: size.width, height: size.height)
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main
        if let v = screen?.visibleFrame {
            frame.origin.x = min(max(frame.minX, v.minX), v.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, v.minY), v.maxY - frame.height)
        }
        panel.setFrame(frame, display: true)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: DesktopWidgetSize.medium.points),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        let restored = panel.setFrameUsingName("ClaudeProfileUsageDesktopWidget")
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
        if !restored || !onScreen, let v = NSScreen.main?.visibleFrame {
            // Default: top-right corner; also the fallback when the saved display is gone.
            panel.setFrame(NSRect(x: v.maxX - 384, y: v.maxY - 190, width: 364, height: 170), display: false)
        }
        panel.setFrameAutosaveName("ClaudeProfileUsageDesktopWidget")
        self.panel = panel
        return panel
    }
}

enum DesktopWidgetSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var family: WidgetFamily {
        switch self {
        case .small: .systemSmall
        case .medium: .systemMedium
        case .large: .systemLarge
        }
    }

    var points: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        }
    }
}

struct DesktopWidgetView: View {
    @ObservedObject var store: UsageStore
    let size: DesktopWidgetSize

    var body: some View {
        WidgetContentView(snapshot: WidgetSnapshot(accounts: store.accounts, updatedAt: store.lastUpdated ?? store.now),
                          family: size.family)
            .padding(16)
            .frame(width: size.points.width, height: size.points.height)
            .clipped()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contextMenu {
                Picker("Size", selection: $store.desktopWidgetSize) {
                    ForEach(DesktopWidgetSize.allCases) { Text($0.title).tag($0) }
                }
                Button("Refresh Now") { Task { await store.refresh() } }
                Button("Hide Desktop Widget") { store.desktopWidgetEnabled = false }
            }
    }
}
