import SwiftUI
import UsageCore

struct PanelView: View {
    @ObservedObject var store: UsageStore
    /// The standalone window already shows the title in its title bar and needs no "Open in Window".
    var isWindow = false
    var openWindow: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 360)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if !isWindow {
                Text("Claude Profile Usage").font(.headline)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                if store.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoading)
            .help("Refresh now")

            Menu {
                Toggle("Refresh expired tokens", isOn: $store.refreshExpiredTokens)
                Toggle("Show in Dock", isOn: $store.showDockIcon)
                Toggle("Desktop widget", isOn: $store.desktopWidgetEnabled)
                Picker("Desktop widget size", selection: $store.desktopWidgetSize) {
                    ForEach(DesktopWidgetSize.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!store.desktopWidgetEnabled)
                if !isWindow {
                    Button("Open in Window", action: openWindow)
                }
                Button("Open Profiles Folder") { store.openProfilesFolder() }
                Divider()
                Button("Quit Claude Profile Usage") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var list: some View {
        if store.accounts.isEmpty {
            VStack(spacing: 6) {
                if store.isLoading || store.lastUpdated == nil {
                    ProgressView()
                } else {
                    Text("No claude-profile accounts found").foregroundStyle(.secondary)
                    Text(ProfileDiscovery.defaultRoot.path).font(.caption).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.accounts) { AccountCardView(account: $0, now: store.now) }
                }
                .padding(12)
            }
            .frame(maxHeight: 560)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            if let updated = store.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("Loading…")
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
