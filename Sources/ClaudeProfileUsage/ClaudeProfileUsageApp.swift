import AppKit
import Combine
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
    private var desktopWidget: DesktopWidgetController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = ProcessInfo.processInfo.environment["CPU_RENDER_ICON"] {
            let ok = ScreenshotRenderer.renderIcon(to: URL(fileURLWithPath: path))
            exit(ok ? 0 : 1)
        }
        if let dir = ProcessInfo.processInfo.environment["CPU_RENDER"] {
            Task {
                await store.refresh()
                ScreenshotRenderer.renderAll(to: URL(fileURLWithPath: dir), store: store)
                NSApp.terminate(nil)
            }
            return
        }
        store.start()
        store.$showDockIcon
            .removeDuplicates()
            .sink { [weak self] show in
                NSApp.setActivationPolicy(show ? .regular : .accessory)
                // Switching policy can hide the main menu or drop an open window behind others.
                if self?.window?.isVisible == true { NSApp.activate(ignoringOtherApps: true) }
            }
            .store(in: &cancellables)
        desktopWidget = DesktopWidgetController(store: store)
    }

    /// Closing the window must not quit the app; it keeps running in the menu bar / Dock.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon, or launching the app again (Spotlight, Finder, `open`), shows the
    /// window, so it stays reachable when the menu bar is too crowded to show the icon.
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
