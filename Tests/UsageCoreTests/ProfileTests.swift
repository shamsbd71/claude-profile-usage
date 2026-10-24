import Foundation
import Testing
@testable import UsageCore

@Test func hashMatchesClaudeCode() {
    #expect(ProfileDiscovery.keychainService(forConfigDir: "/Users/alex/.local/share/claude-profiles/personal") == "Claude Code-credentials-13cbcb4f")
    #expect(ProfileDiscovery.keychainService(forConfigDir: "/Users/alex/.local/share/claude-profiles/work") == "Claude Code-credentials-958c5674")
    #expect(ProfileDiscovery.keychainService(forConfigDir: "/Users/alex/.local/share/claude-profiles/work/") == "Claude Code-credentials-958c5674")
}

@Test func discoversProfilesDefaultFirst() throws {
    let root = makeTempDir(), home = makeTempDir()
    let fm = FileManager.default
    for name in ["a", "b", "c", ".hidden"] {
        try fm.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    try fixture("claude-json-sample.json").write(to: root.appendingPathComponent("b/.claude.json"))
    try Data("{not json".utf8).write(to: root.appendingPathComponent("c/.claude.json"))
    try Data("b".utf8).write(to: root.appendingPathComponent(".default"))
    try Data("x".utf8).write(to: root.appendingPathComponent("stray-file"))

    let ps = ProfileDiscovery.discover(root: root, home: home)
    #expect(ps.map(\.id) == ["b", "a", "c"])
    #expect(ps[0].isDefault && ps[0].email == "someone@example.com" && ps[0].organization == "Example Org")
    #expect(!ps[1].isDefault)
    #expect(ps[1].email == nil && ps[2].email == nil)
    #expect(ps[0].keychainService == ProfileDiscovery.keychainService(forConfigDir: root.appendingPathComponent("b").path))
}

@Test func includesPlainClaudeHomeWhenLoggedIn() throws {
    let root = makeTempDir(), home = makeTempDir()
    try fixture("claude-json-sample.json").write(to: home.appendingPathComponent(".claude.json"))
    let ps = ProfileDiscovery.discover(root: root, home: home)
    #expect(ps.map(\.id) == ["~/.claude"])
    #expect(ps.first?.keychainService == "Claude Code-credentials")
    #expect(ps.first?.email == "someone@example.com")
}

@Test func missingRootIsEmpty() {
    let ps = ProfileDiscovery.discover(root: URL(fileURLWithPath: "/nonexistent-\(UUID())"), home: makeTempDir())
    #expect(ps.isEmpty)
}

@Test func plainClaudeHomeSkippedWhenEmailAlreadyAProfile() throws {
    let root = makeTempDir(), home = makeTempDir()
    try FileManager.default.createDirectory(at: root.appendingPathComponent("work"), withIntermediateDirectories: true)
    try fixture("claude-json-sample.json").write(to: root.appendingPathComponent("work/.claude.json"))
    try fixture("claude-json-sample.json").write(to: home.appendingPathComponent(".claude.json"))
    #expect(ProfileDiscovery.discover(root: root, home: home).map(\.id) == ["work"])
}

@Test func skipsClaudeCodeLegacyLockDirs() throws {
    let root = makeTempDir(), home = makeTempDir()
    for name in ["work", "work.lock"] {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
    }
    #expect(ProfileDiscovery.discover(root: root, home: home).map(\.id) == ["work"])
}
