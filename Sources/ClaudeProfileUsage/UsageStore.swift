import AppKit
import Foundation
import UsageCore
import WidgetKit

@MainActor
final class UsageStore: ObservableObject {
    static let pollInterval: UInt64 = 300
    static let tickInterval: UInt64 = 30
    private static let refreshKey = "refreshExpiredTokens"

    @Published private(set) var accounts: [DisplayAccount] = []
    @Published private(set) var now = Date()
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isLoading = false
    @Published var refreshExpiredTokens: Bool {
        didSet { UserDefaults.standard.set(refreshExpiredTokens, forKey: Self.refreshKey) }
    }

    private var loops: [Task<Void, Never>] = []
    /// `CPU_DEMO=1` shows fictional accounts instead of reading the Keychain.
    let isDemo = ProcessInfo.processInfo.environment["CPU_DEMO"] != nil

    init() {
        refreshExpiredTokens = UserDefaults.standard.object(forKey: Self.refreshKey) as? Bool ?? true
    }

    func start() {
        guard loops.isEmpty else { return }
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: Self.pollInterval * 1_000_000_000)
            }
        })
        loops.append(Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.tickInterval * 1_000_000_000)
                self?.now = Date()
            }
        })
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        if isDemo {
            now = Date()
            accounts = DemoData.accounts(now: now)
            lastUpdated = now
            return
        }
        let service = UsageService(keychain: SecurityCLIKeychain(), http: URLSessionTransport(),
                                   allowRefresh: refreshExpiredTokens)
        let profiles = ProfileDiscovery.discover()
        let results = await service.fetchAll(profiles)
        accounts = StaleMerge.merge(new: results, previous: accounts)
        now = Date()
        lastUpdated = now
        publishToWidget()
    }

    private func publishToWidget() {
        let snapshot = WidgetSnapshot(accounts: accounts, updatedAt: now)
        try? snapshot.write(to: WidgetSnapshot.fileURL(home: WidgetSnapshot.realHome))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Highest started-window percent across all accounts, for the menu bar title.
    var menuTitle: String {
        let peak = accounts.compactMap { $0.snapshot?.maxActivePercent }.max()
        return peak.map(UsageFormat.percent) ?? "–"
    }

    func openProfilesFolder() {
        NSWorkspace.shared.open(ProfileDiscovery.defaultRoot)
    }
}
