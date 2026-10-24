import Foundation

public enum RefreshLockError: Error, Equatable {
    case busy
}

public protocol RefreshLocking: Sendable {
    func withLock<T>(configDir: URL, _ body: () async throws -> T) async throws -> T
}

/// Takes the same locks Claude Code takes around an OAuth refresh (proper-lockfile style:
/// an atomic mkdir, considered stale after 60 s): `<configDir>/.oauth_refresh.lock` and the legacy
/// `<realpath(configDir)>.lock`. While we hold them, Claude Code waits instead of refreshing the
/// same token concurrently, and vice versa.
public struct FileRefreshLock: RefreshLocking {
    static let staleAfter: TimeInterval = 60
    let timeout: TimeInterval

    public init(timeout: TimeInterval = 10) {
        self.timeout = timeout
    }

    public func withLock<T>(configDir: URL, _ body: () async throws -> T) async throws -> T {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: configDir.path, isDirectory: &isDir), isDir.boolValue else {
            return try await body()
        }
        let primary = configDir.appendingPathComponent(".oauth_refresh.lock").path
        let legacy = configDir.resolvingSymlinksInPath().path + ".lock"
        let deadline = Date().addingTimeInterval(timeout)

        try await acquire(primary, deadline: deadline)
        defer { rmdir(primary) }
        try await acquire(legacy, deadline: deadline)
        defer { rmdir(legacy) }
        return try await body()
    }

    private func acquire(_ path: String, deadline: Date) async throws {
        while true {
            if mkdir(path, 0o755) == 0 { return }
            guard errno == EEXIST else { throw RefreshLockError.busy }
            if let modified = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date,
               Date().timeIntervalSince(modified) > Self.staleAfter {
                try? FileManager.default.removeItem(atPath: path)
                continue
            }
            if Date() >= deadline { throw RefreshLockError.busy }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }
}
