import Foundation
import Testing
@testable import UsageCore

@Test func parsesSample() throws {
    let t = try CredentialBlob.parse(fixture("credentials-sample.json"))
    #expect(t.accessToken == "sk-ant-oat01-FAKE" && t.refreshToken == "sk-ant-ort01-FAKE")
    #expect(t.subscriptionType == "max" && t.rateLimitTier == "default_claude_max_5x")
    #expect(t.expiresAt == Date(timeIntervalSince1970: 1792876466.442))
    #expect(t.scopes.contains("user:profile"))
}

@Test func missingOauthThrows() {
    #expect(throws: CredentialError.noClaudeAiOauth) { try CredentialBlob.parse(Data(#"{"mcpOAuth":{}}"#.utf8)) }
    #expect(throws: CredentialError.malformed) { try CredentialBlob.parse(Data("nope".utf8)) }
}

@Test func mergeKeepsOtherKeys() throws {
    let out = try CredentialBlob.merging(accessToken: "A2", refreshToken: "R2",
                                         expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
                                         into: fixture("credentials-sample.json"))
    let obj = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
    let o = try #require(obj["claudeAiOauth"] as? [String: Any])
    #expect(o["accessToken"] as? String == "A2" && o["refreshToken"] as? String == "R2")
    #expect((o["expiresAt"] as? NSNumber)?.int64Value == 2_000_000_000_000)
    #expect(String(data: out, encoding: .utf8)!.contains("\"expiresAt\":2000000000000"))
    #expect(o["subscriptionType"] as? String == "max" && (o["scopes"] as? [String])?.count == 3)
    #expect(obj["mcpOAuth"] != nil)
}

@Test func parsesSecurityAccountAttribute() {
    let dump = """
    keychain: "/Users/alex/Library/Keychains/login.keychain-db"
    attributes:
        "acct"<blob>="alex"
        "svce"<blob>="Claude Code-credentials-958c5674"
    """
    #expect(SecurityCLIKeychain.parseAccount(dump) == "alex")
    #expect(SecurityCLIKeychain.parseAccount("nothing") == nil)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["CU_KEYCHAIN_TEST"] != nil, "manual: touches the login Keychain"))
func keychainRoundTrip() throws {
    let kc = SecurityCLIKeychain()
    let svc = "claude-usage-selftest"
    for size in [40, 9000] {
        let blob = Data(("{\"claudeAiOauth\":{\"accessToken\":\"" + String(repeating: "x", count: size) + "\"}}").utf8)
        try kc.write(service: svc, account: NSUserName(), data: blob)
        let back = try #require(try kc.read(service: svc))
        #expect(back.data == blob && back.account == NSUserName())
    }
    #expect(try kc.read(service: "claude-usage-does-not-exist") == nil)
    for profile in ProfileDiscovery.discover() {
        if let real = try kc.read(service: profile.keychainService) {
            print("\(profile.id): \(real.data.count) bytes, parses: \((try? CredentialBlob.parse(real.data)) != nil)")
        }
    }
}

@Test func decodesHexPasswordOutput() {
    #expect(SecurityCLIKeychain.decodePassword(Data("{\"a\":1}\n".utf8)) == Data("{\"a\":1}".utf8))
    #expect(SecurityCLIKeychain.decodePassword(Data("7b7d\n".utf8)) == Data("{}".utf8))
}

@Test func hungSecurityCallTimesOut() throws {
    let start = Date()
    #expect(throws: KeychainError.timedOut) {
        _ = try SecurityCLIKeychain.run(["5"], tool: "/bin/sleep", timeout: 0.5)
    }
    #expect(Date().timeIntervalSince(start) < 3)
}

@Test func largeStderrDoesNotDeadlock() throws {
    let r = try SecurityCLIKeychain.run(["-c", "head -c 200000 /dev/zero >&2; echo ok"], tool: "/bin/sh", timeout: 5)
    #expect(r.status == 0 && String(decoding: r.stdout, as: UTF8.self) == "ok\n")
}
