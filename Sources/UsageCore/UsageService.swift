import Foundation

public enum AccountStatus: Equatable, Sendable {
    case ok(UsageSnapshot)
    case noLogin
    case authExpired(String)
    case rateLimited
    case failed(String)
}

public struct AccountUsage: Identifiable, Equatable, Sendable {
    public let profile: Profile
    public let plan: String
    public let status: AccountStatus
    public var id: String { profile.id }

    public init(profile: Profile, plan: String, status: AccountStatus) {
        self.profile = profile
        self.plan = plan
        self.status = status
    }
}

public final class UsageService: @unchecked Sendable {
    /// Refresh when the access token expires within this many seconds.
    static let expiryMargin: TimeInterval = 60

    private let keychain: KeychainAccess
    private let http: HTTPTransport
    private let lock: RefreshLocking
    private let allowRefresh: Bool
    private let now: @Sendable () -> Date

    /// Refreshed tokens we could not save, keyed by Keychain service, with the refresh token they
    /// replaced. The next fetch re-saves them instead of spending the (already used) old one.
    private var rescued: [String: (spent: String, tokens: RefreshedTokens)] = [:]
    private let rescuedLock = NSLock()

    public init(keychain: KeychainAccess, http: HTTPTransport, allowRefresh: Bool,
                lock: RefreshLocking = FileRefreshLock(),
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.keychain = keychain
        self.http = http
        self.lock = lock
        self.allowRefresh = allowRefresh
        self.now = now
    }

    public func fetchAll(_ profiles: [Profile]) async -> [AccountUsage] {
        await withTaskGroup(of: (Int, AccountUsage).self) { group in
            for (i, p) in profiles.enumerated() {
                group.addTask { (i, await self.fetch(p)) }
            }
            var results = [AccountUsage?](repeating: nil, count: profiles.count)
            for await (i, r) in group { results[i] = r }
            return results.compactMap { $0 }
        }
    }

    public func fetch(_ profile: Profile) async -> AccountUsage {
        let item: (data: Data, account: String)?
        do {
            item = try keychain.read(service: profile.keychainService)
        } catch {
            return AccountUsage(profile: profile, plan: "—", status: .failed("Keychain read failed"))
        }
        guard let item, let tokens = try? CredentialBlob.parse(item.data) else {
            return AccountUsage(profile: profile, plan: "—", status: .noLogin)
        }
        let plan = UsageFormat.planLabel(subscriptionType: tokens.subscriptionType, rateLimitTier: tokens.rateLimitTier)
        let status = await fetchStatus(profile, tokens: tokens)
        return AccountUsage(profile: profile, plan: plan, status: status)
    }

    private func fetchStatus(_ profile: Profile, tokens initial: OAuthTokens) async -> AccountStatus {
        var tokens = initial
        var refreshAttempted = false

        if tokens.expiresAt.timeIntervalSince(now()) < Self.expiryMargin {
            guard allowRefresh else { return .authExpired(Self.refreshDisabledHint(profile)) }
            switch await refreshIfStillStale(profile, failedToken: nil) {
            case .tokens(let t, let posted): tokens = t; refreshAttempted = posted
            case .rejected: return .authExpired(Self.loginHint(profile))
            case .gone: return .noLogin
            case .failed(let msg): return .failed(msg)
            }
        }

        do {
            var (status, data) = try await getUsage(tokens.accessToken)
            if status == 401 {
                guard allowRefresh, !refreshAttempted else { return .authExpired(Self.loginHint(profile)) }
                switch await refreshIfStillStale(profile, failedToken: tokens.accessToken) {
                case .tokens(let t, _): tokens = t
                case .rejected: return .authExpired(Self.loginHint(profile))
                case .gone: return .noLogin
                case .failed(let msg): return .failed(msg)
                }
                (status, data) = try await getUsage(tokens.accessToken)
            }
            switch status {
            case 200:
                guard let snap = try? UsageDecoder.decode(data, fetchedAt: now()) else {
                    return .failed("Unexpected usage response")
                }
                return .ok(snap)
            case 401, 403: return .authExpired(Self.loginHint(profile))
            case 429: return .rateLimited
            default: return .failed("Usage request failed (HTTP \(status))")
            }
        } catch {
            return .failed(Self.describe(error))
        }
    }

    private func getUsage(_ accessToken: String) async throws -> (Int, Data) {
        var req = URLRequest(url: Endpoints.usage)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(Endpoints.betaHeader, forHTTPHeaderField: "anthropic-beta")
        req.setValue(Endpoints.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await http.send(req)
        return (response.statusCode, data)
    }

    private enum RefreshOutcome {
        case tokens(OAuthTokens, posted: Bool)
        case rejected
        /// The Keychain item disappeared (the user logged out).
        case gone
        case failed(String)
    }

    /// Under Claude Code's refresh lock: re-read the Keychain (Claude Code may already have
    /// refreshed), and only if the stored token is still stale (or is the one the server just
    /// rejected) spend the refresh token and save the rotated pair back.
    private func refreshIfStillStale(_ profile: Profile, failedToken: String?) async -> RefreshOutcome {
        do {
            return try await lock.withLock(configDir: profile.configDir) {
                await refreshLocked(profile, failedToken: failedToken)
            }
        } catch {
            // Someone else held the lock for the whole wait — most likely Claude Code refreshing.
            if let item = try? keychain.read(service: profile.keychainService),
               let stored = try? CredentialBlob.parse(item.data),
               isFresh(stored), stored.accessToken != failedToken {
                return .tokens(stored, posted: false)
            }
            return .failed("Another process is refreshing this login")
        }
    }

    private func refreshLocked(_ profile: Profile, failedToken: String?) async -> RefreshOutcome {
        let service = profile.keychainService
        guard let item = try? keychain.read(service: service) else { return .gone }
        guard let stored = try? CredentialBlob.parse(item.data) else { return .rejected }
        if isFresh(stored) && stored.accessToken != failedToken {
            return .tokens(stored, posted: false)
        }
        if let pending = rescuedLock.withLock({ rescued[service] }), pending.spent == stored.refreshToken {
            return save(pending.tokens, replacing: stored.refreshToken, profile: profile)
        }
        guard !stored.refreshToken.isEmpty else { return .rejected }

        var req = URLRequest(url: Endpoints.token)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Endpoints.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": stored.refreshToken,
            "client_id": Endpoints.clientID,
        ])

        let data: Data, response: HTTPURLResponse
        do {
            (data, response) = try await http.send(req)
        } catch {
            return .failed(Self.describe(error))
        }
        switch response.statusCode {
        case 200: break
        case 400, 401, 403:
            // Lost a race with another refresher? Then the Keychain already holds a newer pair.
            if let again = try? keychain.read(service: service),
               let current = try? CredentialBlob.parse(again.data),
               current.refreshToken != stored.refreshToken, isFresh(current) {
                return .tokens(current, posted: true)
            }
            return .rejected
        case 429: return .failed("Token refresh rate limited")
        default: return .failed("Token refresh failed (HTTP \(response.statusCode))")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = obj["access_token"] as? String else {
            return .failed("Unexpected token response")
        }
        let expiresIn = (obj["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        let fresh = RefreshedTokens(
            accessToken: access,
            refreshToken: obj["refresh_token"] as? String ?? stored.refreshToken,
            expiresAt: now().addingTimeInterval(expiresIn),
            refreshTokenExpiresAt: (obj["refresh_token_expires_in"] as? NSNumber).map { now().addingTimeInterval($0.doubleValue) },
            scopes: (obj["scope"] as? String).map { $0.split(separator: " ").map(String.init) },
            subscriptionType: stored.subscriptionType,
            rateLimitTier: stored.rateLimitTier
        )
        return save(fresh, replacing: stored.refreshToken, profile: profile)
    }

    /// Merges into the item as it is *now* (not as read before the network call), so changes
    /// another process made meanwhile survive. Never re-creates a deleted item.
    private func save(_ fresh: RefreshedTokens, replacing spent: String, profile: Profile) -> RefreshOutcome {
        let service = profile.keychainService
        guard let item = try? keychain.read(service: service) else {
            clearRescue(service)
            return .gone
        }
        if let current = try? CredentialBlob.parse(item.data), current.refreshToken != spent {
            // Another process rotated the login while we were refreshing; theirs is what's stored.
            clearRescue(service)
            return .tokens(current, posted: true)
        }
        guard let merged = try? CredentialBlob.merging(
            accessToken: fresh.accessToken, refreshToken: fresh.refreshToken, expiresAt: fresh.expiresAt,
            refreshTokenExpiresAt: fresh.refreshTokenExpiresAt, scopes: fresh.scopes, into: item.data) else {
            return .failed("Couldn't update the stored login")
        }
        for _ in 0..<2 {
            if (try? keychain.write(service: service, account: item.account, data: merged)) != nil {
                clearRescue(service)
                return .tokens(fresh.oauthTokens, posted: true)
            }
        }
        rescuedLock.withLock { rescued[service] = (spent, fresh) }
        return .failed("Couldn't save the refreshed login to the Keychain — will retry")
    }

    private func clearRescue(_ service: String) {
        _ = rescuedLock.withLock { rescued.removeValue(forKey: service) }
    }

    private func isFresh(_ t: OAuthTokens) -> Bool {
        t.expiresAt.timeIntervalSince(now()) >= Self.expiryMargin
    }

    static func refreshDisabledHint(_ profile: Profile) -> String {
        "Token expired (refresh disabled) — use it in Claude Code or enable refresh"
    }

    static func loginHint(_ profile: Profile) -> String {
        profile.id == ProfileDiscovery.plainProfileID
            ? "Login expired — run: claude"
            : "Login expired — run: claude-profile use \(profile.id) && claude"
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? URLError {
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost: return "Offline"
            case .timedOut: return "Request timed out"
            default: return "Network error (\(e.code.rawValue))"
            }
        }
        return "Request failed"
    }
}

struct RefreshedTokens: Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let refreshTokenExpiresAt: Date?
    let scopes: [String]?
    let subscriptionType: String?
    let rateLimitTier: String?

    var oauthTokens: OAuthTokens {
        OAuthTokens(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt,
                    subscriptionType: subscriptionType, rateLimitTier: rateLimitTier, scopes: scopes ?? [])
    }
}
