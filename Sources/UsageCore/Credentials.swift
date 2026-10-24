import Foundation

public struct OAuthTokens: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let subscriptionType: String?
    public let rateLimitTier: String?
    public let scopes: [String]
}

public enum CredentialError: Error, Equatable {
    case noClaudeAiOauth
    case malformed
}

/// The JSON Claude Code stores in its Keychain item.
public enum CredentialBlob {
    public static func parse(_ data: Data) throws -> OAuthTokens {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CredentialError.malformed
        }
        guard let o = obj["claudeAiOauth"] as? [String: Any],
              let access = o["accessToken"] as? String else {
            throw CredentialError.noClaudeAiOauth
        }
        let expiresMs = (o["expiresAt"] as? NSNumber)?.doubleValue ?? 0
        return OAuthTokens(
            accessToken: access,
            refreshToken: o["refreshToken"] as? String ?? "",
            expiresAt: Date(timeIntervalSince1970: expiresMs / 1000),
            subscriptionType: o["subscriptionType"] as? String,
            rateLimitTier: o["rateLimitTier"] as? String,
            scopes: o["scopes"] as? [String] ?? []
        )
    }

    /// Replaces only the rotated token fields; every other key in the blob is preserved.
    /// `refreshTokenExpiresAt` and `scopes` are updated only when the token response supplied them.
    public static func merging(accessToken: String, refreshToken: String, expiresAt: Date,
                               refreshTokenExpiresAt: Date? = nil, scopes: [String]? = nil,
                               into original: Data) throws -> Data {
        guard var obj = try? JSONSerialization.jsonObject(with: original) as? [String: Any] else {
            throw CredentialError.malformed
        }
        guard var o = obj["claudeAiOauth"] as? [String: Any] else { throw CredentialError.noClaudeAiOauth }
        o["accessToken"] = accessToken
        o["refreshToken"] = refreshToken
        o["expiresAt"] = milliseconds(expiresAt)
        if let refreshTokenExpiresAt { o["refreshTokenExpiresAt"] = milliseconds(refreshTokenExpiresAt) }
        if let scopes, !scopes.isEmpty { o["scopes"] = scopes }
        obj["claudeAiOauth"] = o
        return try JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes])
    }

    private static func milliseconds(_ d: Date) -> NSNumber {
        NSNumber(value: Int64((d.timeIntervalSince1970 * 1000).rounded()))
    }
}
