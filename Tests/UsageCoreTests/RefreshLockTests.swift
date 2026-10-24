import Foundation
import Testing
@testable import UsageCore

private func configDir() throws -> URL {
    let dir = makeTempDir().appendingPathComponent("work")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func lockCreatesAndRemovesBothClaudeCodeLocks() async throws {
    let dir = try configDir()
    let fm = FileManager.default
    let seen = try await FileRefreshLock(timeout: 1).withLock(configDir: dir) {
        (fm.fileExists(atPath: dir.appendingPathComponent(".oauth_refresh.lock").path),
         fm.fileExists(atPath: dir.resolvingSymlinksInPath().path + ".lock"))
    }
    #expect(seen.0 && seen.1)
    #expect(!fm.fileExists(atPath: dir.appendingPathComponent(".oauth_refresh.lock").path))
    #expect(!fm.fileExists(atPath: dir.resolvingSymlinksInPath().path + ".lock"))
}

@Test func heldLockTimesOut() async throws {
    let dir = try configDir()
    try FileManager.default.createDirectory(at: dir.appendingPathComponent(".oauth_refresh.lock"), withIntermediateDirectories: false)
    await #expect(throws: RefreshLockError.busy) {
        try await FileRefreshLock(timeout: 0.5).withLock(configDir: dir) { 1 }
    }
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".oauth_refresh.lock").path))
}

@Test func staleLockIsTakenOver() async throws {
    let dir = try configDir()
    let lock = dir.appendingPathComponent(".oauth_refresh.lock")
    try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-120)], ofItemAtPath: lock.path)
    let v = try await FileRefreshLock(timeout: 1).withLock(configDir: dir) { 7 }
    #expect(v == 7)
}

@Test func missingConfigDirRunsUnlocked() async throws {
    let v = try await FileRefreshLock(timeout: 0.2).withLock(configDir: URL(fileURLWithPath: "/nonexistent-\(UUID())")) { 3 }
    #expect(v == 3)
}
