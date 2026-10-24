import Foundation
import Testing
@testable import UsageCore

private let now = Date(timeIntervalSince1970: 1_792_850_000)

private func blob(access: String, expiresIn: TimeInterval, refresh: String = "R1", mcp: String = "x",
                  sub: String = "max", tier: String = "default_claude_max_5x") -> Data {
    let ms = Int64((now.timeIntervalSince1970 + expiresIn) * 1000)
    return Data("""
    {"claudeAiOauth":{"accessToken":"\(access)","refreshToken":"\(refresh)","expiresAt":\(ms),"refreshTokenExpiresAt":1,"scopes":["user:profile"],"subscriptionType":"\(sub)","rateLimitTier":"\(tier)"},"mcpOAuth":{"\(mcp)":{"accessToken":"keep"}}}
    """.utf8)
}

private func profile(_ id: String = "work") -> Profile {
    Profile(id: id, configDir: URL(fileURLWithPath: "/tmp/\(id)"), email: "\(id)@example.com",
            organization: nil, keychainService: "svc-\(id)", isDefault: false)
}

final class FakeKeychain: KeychainAccess, @unchecked Sendable {
    private let lock = NSLock()
    private var queues: [String: [Data?]]
    private(set) var writes: [(service: String, account: String, data: Data)] = []
    private(set) var failedWrites = 0
    var writeFailures = 0

    /// Each read pops the next value for that service; the last one repeats. nil = item absent.
    init(_ queues: [String: [Data?]]) { self.queues = queues }

    func read(service: String) throws -> (data: Data, account: String)? {
        lock.lock(); defer { lock.unlock() }
        guard var q = queues[service], let first = q.first else { return nil }
        if q.count > 1 { q.removeFirst(); queues[service] = q }
        return first.map { ($0, "alex") }
    }

    func write(service: String, account: String, data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        if writeFailures > 0 {
            writeFailures -= 1
            failedWrites += 1
            throw KeychainError.commandFailed(51)
        }
        writes.append((service, account, data))
        queues[service] = [data]
    }
}

final class FakeTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async throws -> (Int, Data)
    private let lock = NSLock()
    private var usageResponses: [(Int, Data)]
    private let tokenResponse: (Int, Data)
    private let delay: (@Sendable (URLRequest) -> UInt64)?
    private let error: Error?
    private(set) var requests: [URLRequest] = []

    init(usage: [(Int, Data)] = [(200, fixture("usage-max-session-active.json"))],
         token: (Int, Data) = (200, Data(#"{"access_token":"A2","refresh_token":"R2","expires_in":28800}"#.utf8)),
         delay: (@Sendable (URLRequest) -> UInt64)? = nil, error: Error? = nil) {
        self.usageResponses = usage
        self.tokenResponse = token
        self.delay = delay
        self.error = error
    }

    var usageRequests: [URLRequest] { lock.withLock { requests.filter { $0.url == Endpoints.usage } } }
    var tokenRequests: [URLRequest] { lock.withLock { requests.filter { $0.url == Endpoints.token } } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if let delay { try await Task.sleep(nanoseconds: delay(request)) }
        let (status, data): (Int, Data) = try lock.withLock {
            requests.append(request)
            if let error { throw error }
            if request.url == Endpoints.token { return tokenResponse }
            return usageResponses.count > 1 ? usageResponses.removeFirst() : usageResponses[0]
        }
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private func service(_ kc: KeychainAccess, _ http: HTTPTransport, refresh: Bool = true) -> UsageService {
    UsageService(keychain: kc, http: http, allowRefresh: refresh, now: { now })
}

@Test func freshTokenNoRefresh() async {
    let kc = FakeKeychain(["svc-work": [blob(access: "A1", expiresIn: 3600)]])
    let http = FakeTransport()
    let r = await service(kc, http).fetch(profile())
    guard case .ok(let snap) = r.status else { Issue.record("expected ok, got \(r.status)"); return }
    #expect(snap.limits.count == 3 && snap.fetchedAt == now)
    #expect(r.plan == "Max 5x" && r.id == "work")
    #expect(http.requests.count == 1 && kc.writes.isEmpty)
    let req = http.requests[0]
    #expect(req.httpMethod == "GET" && req.url == Endpoints.usage)
    #expect(req.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer A1")
}

@Test func noKeychainItemIsNoLogin() async {
    let http = FakeTransport()
    let r = await service(FakeKeychain([:]), http).fetch(profile())
    #expect(r.status == .noLogin && r.plan == "—" && http.requests.isEmpty)
}

@Test func blobWithoutOauthIsNoLogin() async {
    let r = await service(FakeKeychain(["svc-work": [Data(#"{"mcpOAuth":{}}"#.utf8)]]), FakeTransport()).fetch(profile())
    #expect(r.status == .noLogin)
}

@Test func expiredButReReadIsFresh() async {
    let kc = FakeKeychain(["svc-work": [blob(access: "OLD", expiresIn: -10), blob(access: "NEW", expiresIn: 3600)]])
    let http = FakeTransport()
    let r = await service(kc, http).fetch(profile())
    guard case .ok = r.status else { Issue.record("expected ok, got \(r.status)"); return }
    #expect(http.tokenRequests.isEmpty && http.usageRequests.count == 1)
    #expect(http.usageRequests[0].value(forHTTPHeaderField: "Authorization") == "Bearer NEW")
    #expect(kc.writes.isEmpty)
}

@Test func expiredRefreshesAndWritesBack() async throws {
    let kc = FakeKeychain(["svc-work": [blob(access: "OLD", expiresIn: -10)]])
    let http = FakeTransport()
    let r = await service(kc, http).fetch(profile())
    guard case .ok = r.status else { Issue.record("expected ok, got \(r.status)"); return }
    #expect(http.usageRequests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer A2")
    let tokenReq = try #require(http.tokenRequests.first)
    #expect(tokenReq.httpMethod == "POST")
    let body = try #require(try JSONSerialization.jsonObject(with: tokenReq.httpBody ?? Data()) as? [String: String])
    #expect(body["grant_type"] == "refresh_token" && body["refresh_token"] == "R1" && body["client_id"] == Endpoints.clientID)
    #expect(kc.writes.count == 1)
    let written = try #require(kc.writes.first)
    #expect(written.service == "svc-work" && written.account == "alex")
    let parsed = try CredentialBlob.parse(written.data)
    #expect(parsed.accessToken == "A2" && parsed.refreshToken == "R2")
    #expect(parsed.expiresAt == now.addingTimeInterval(28800))
    #expect(String(decoding: written.data, as: UTF8.self).contains("mcpOAuth"))
}

@Test func usage401TriggersOneRefreshThenRetry() async {
    let kc = FakeKeychain(["svc-work": [blob(access: "A1", expiresIn: 3600)]])
    let http = FakeTransport(usage: [(401, Data()), (200, fixture("usage-max-session-active.json"))])
    let r = await service(kc, http).fetch(profile())
    guard case .ok = r.status else { Issue.record("expected ok, got \(r.status)"); return }
    #expect(http.tokenRequests.count == 1 && http.usageRequests.count == 2 && kc.writes.count == 1)
}

@Test func repeated401IsAuthExpired() async {
    let kc = FakeKeychain(["svc-work": [blob(access: "A1", expiresIn: 3600)]])
    let http = FakeTransport(usage: [(401, Data())])
    let r = await service(kc, http).fetch(profile())
    guard case .authExpired = r.status else { Issue.record("expected authExpired, got \(r.status)"); return }
    #expect(http.tokenRequests.count == 1 && http.usageRequests.count == 2)
}

@Test func refreshRejectedIsAuthExpired() async {
    let kc = FakeKeychain(["svc-work": [blob(access: "OLD", expiresIn: -10)]])
    let http = FakeTransport(token: (400, Data(#"{"error":"invalid_grant"}"#.utf8)))
    let r = await service(kc, http).fetch(profile())
    guard case .authExpired(let msg) = r.status else { Issue.record("expected authExpired, got \(r.status)"); return }
    #expect(msg.contains("claude-profile use work"))
    #expect(kc.writes.isEmpty && http.usageRequests.isEmpty)
}

@Test func noRefreshFlagSkipsRefresh() async {
    let kc = FakeKeychain(["svc-work": [blob(access: "OLD", expiresIn: -10)]])
    let http = FakeTransport()
    let r = await service(kc, http, refresh: false).fetch(profile())
    guard case .authExpired = r.status else { Issue.record("expected authExpired, got \(r.status)"); return }
    #expect(http.requests.isEmpty && kc.writes.isEmpty)
}

@Test func rateLimited() async {
    let kc = FakeKeychain(["svc-work": [blob(access: "A1", expiresIn: 3600)]])
    let r = await service(kc, FakeTransport(usage: [(429, Data())])).fetch(profile())
    #expect(r.status == .rateLimited)
}

@Test func networkErrorIsFailed() async {
    let kc = FakeKeychain(["svc-work": [blob(access: "A1", expiresIn: 3600)]])
    let r = await service(kc, FakeTransport(error: URLError(.notConnectedToInternet))).fetch(profile())
    guard case .failed(let msg) = r.status else { Issue.record("expected failed, got \(r.status)"); return }
    #expect(!msg.isEmpty && !msg.contains("A1"))
}

@Test func fetchAllPreservesOrder() async {
    let kc = FakeKeychain([
        "svc-a": [blob(access: "TA", expiresIn: 3600)],
        "svc-b": [blob(access: "TB", expiresIn: 3600)],
        "svc-c": [blob(access: "TC", expiresIn: 3600)],
    ])
    let http = FakeTransport(delay: { req in
        switch req.value(forHTTPHeaderField: "Authorization") {
        case "Bearer TA": return 60_000_000
        case "Bearer TB": return 30_000_000
        default: return 0
        }
    })
    let rs = await service(kc, http).fetchAll([profile("a"), profile("b"), profile("c")])
    #expect(rs.map(\.id) == ["a", "b", "c"])
}

// MARK: - Final review fixes

@Test func writeBackMergesIntoFreshBlob() async throws {
    // fetch read, re-read under lock, pre-write read (Claude Code saved a new MCP login meanwhile)
    let kc = FakeKeychain(["svc-work": [blob(access: "OLD", expiresIn: -10), blob(access: "OLD", expiresIn: -10),
                                        blob(access: "OLD", expiresIn: -10, mcp: "newServer")]])
    let r = await service(kc, FakeTransport()).fetch(profile())
    guard case .ok = r.status else { Issue.record("expected ok, got \(r.status)"); return }
    let written = try #require(kc.writes.first)
    #expect(String(decoding: written.data, as: UTF8.self).contains("newServer"))
    #expect(try CredentialBlob.parse(written.data).accessToken == "A2")
}

@Test func otherProcessRotatedDuringPostWins() async {
    let kc = FakeKeychain(["svc-work": [blob(access: "OLD", expiresIn: -10), blob(access: "OLD", expiresIn: -10),
                                        blob(access: "A9", expiresIn: 3600, refresh: "R9")]])
    let http = FakeTransport()
    let r = await service(kc, http).fetch(profile())
    guard case .ok = r.status else { Issue.record("expected ok, got \(r.status)"); return }
    #expect(kc.writes.isEmpty)
    #expect(http.usageRequests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer A9")
}

@Test func itemDeletedDuringPostIsNotRecreated() async {
    let kc = FakeKeychain(["svc-work": [blob(access: "OLD", expiresIn: -10), blob(access: "OLD", expiresIn: -10), nil]])
    let r = await service(kc, FakeTransport()).fetch(profile())
    #expect(kc.writes.isEmpty)
    #expect(r.status == .noLogin)
}

@Test func writeFailureIsSurfacedAndRescuedNextTime() async throws {
    let kc = FakeKeychain(["svc-work": [blob(access: "OLD", expiresIn: -10)]])
    kc.writeFailures = 2
    let http = FakeTransport()
    let svc = service(kc, http)
    let first = await svc.fetch(profile())
    guard case .failed(let msg) = first.status else { Issue.record("expected failed, got \(first.status)"); return }
    #expect(msg.contains("Keychain") && kc.failedWrites == 2 && http.tokenRequests.count == 1)
    // Next poll: Keychain still holds the spent R1 — re-save the pair we hold instead of spending R1 again.
    let second = await svc.fetch(profile())
    guard case .ok = second.status else { Issue.record("expected ok, got \(second.status)"); return }
    #expect(http.tokenRequests.count == 1 && kc.writes.count == 1)
    #expect(try CredentialBlob.parse(kc.writes[0].data).accessToken == "A2")
}

@Test func refreshStoresRefreshExpiryAndScopes() async throws {
    let kc = FakeKeychain(["svc-work": [blob(access: "OLD", expiresIn: -10)]])
    let http = FakeTransport(token: (200, Data(#"{"access_token":"A2","refresh_token":"R2","expires_in":28800,"refresh_token_expires_in":2592000,"scope":"user:profile user:inference"}"#.utf8)))
    _ = await service(kc, http).fetch(profile())
    let written = try #require(kc.writes.first)
    let o = try #require((try JSONSerialization.jsonObject(with: written.data) as? [String: Any])?["claudeAiOauth"] as? [String: Any])
    #expect((o["refreshTokenExpiresAt"] as? NSNumber)?.int64Value == Int64((now.timeIntervalSince1970 + 2592000) * 1000))
    #expect(o["scopes"] as? [String] == ["user:profile", "user:inference"])
}

@Test func refreshWithoutExpiryKeepsStoredValues() async throws {
    let kc = FakeKeychain(["svc-work": [blob(access: "OLD", expiresIn: -10)]])
    _ = await service(kc, FakeTransport()).fetch(profile())
    let o = try #require((try JSONSerialization.jsonObject(with: kc.writes[0].data) as? [String: Any])?["claudeAiOauth"] as? [String: Any])
    #expect((o["refreshTokenExpiresAt"] as? NSNumber)?.int64Value == 1 && o["scopes"] as? [String] == ["user:profile"])
}

@Test func rejectedButRotatedElsewhereUsesStored() async {
    // fetch read, re-read under lock (still OLD), refresh rejected, re-read shows Claude Code rotated it
    let kc = FakeKeychain(["svc-work": [blob(access: "OLD", expiresIn: -10), blob(access: "OLD", expiresIn: -10),
                                        blob(access: "A9", expiresIn: 3600, refresh: "R9")]])
    let http = FakeTransport(token: (400, Data(#"{"error":"invalid_grant"}"#.utf8)))
    let r = await service(kc, http).fetch(profile())
    guard case .ok = r.status else { Issue.record("expected ok, got \(r.status)"); return }
    #expect(http.usageRequests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer A9")
}

@Test func refreshDisabledMessageIsNotLoginExpired() async {
    let kc = FakeKeychain(["svc-work": [blob(access: "OLD", expiresIn: -10)]])
    let r = await service(kc, FakeTransport(), refresh: false).fetch(profile())
    guard case .authExpired(let msg) = r.status else { Issue.record("expected authExpired, got \(r.status)"); return }
    #expect(msg.contains("refresh disabled"))
}
