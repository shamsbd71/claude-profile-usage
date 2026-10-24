import AppKit
import SwiftUI
import UsageCore

@main
struct ClaudeProfileUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: delegate.store, openWindow: { delegate.showWindow() })
        } label: {
            MenuBarLabel(store: delegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.dots.needle.67percent")
            Text(store.menuTitle).monospacedDigit()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = ProcessInfo.processInfo.environment["CPU_RENDER"] {
            Task {
                await store.refresh()
                ScreenshotRenderer.renderAll(to: URL(fileURLWithPath: dir), store: store)
                NSApp.terminate(nil)
            }
            return
        }
        store.start()
    }


    /// Launching the app again (Spotlight, Finder, `open`) while it runs shows the window, so it
    /// stays reachable when the menu bar is too crowded to show the icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func showWindow() {
        if window == nil {
            let host = NSHostingController(rootView: PanelView(store: store, isWindow: true))
            let w = NSWindow(contentViewController: host)
            w.title = "Claude Profile Usage"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("ClaudeUsageWindow")
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
