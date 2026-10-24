import CryptoKit
import Foundation

public struct Profile: Identifiable, Equatable, Sendable {
    /// Profile name, or "~/.claude" for the plain (unmanaged) config dir.
    public let id: String
    public let configDir: URL
    public let email: String?
    public let organization: String?
    public let keychainService: String
    public let isDefault: Bool

    public init(id: String, configDir: URL, email: String?, organization: String?, keychainService: String, isDefault: Bool) {
        self.id = id
        self.configDir = configDir
        self.email = email
        self.organization = organization
        self.keychainService = keychainService
        self.isDefault = isDefault
    }
}

public enum ProfileDiscovery {
    public static let plainServiceName = "Claude Code-credentials"
    public static let plainProfileID = "~/.claude"

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/claude-profiles")
    }

    /// Claude Code names its Keychain item after the first 8 hex chars of sha256(CLAUDE_CONFIG_DIR).
    public static func keychainService(forConfigDir path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        let hex = SHA256.hash(data: Data(p.utf8)).map { String(format: "%02x", $0) }.joined()
        return "\(plainServiceName)-\(hex.prefix(8))"
    }

    public static func discover(root: URL = defaultRoot, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Profile] {
        let fm = FileManager.default
        let defaultName = (try? String(contentsOf: root.appendingPathComponent(".default"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var profiles: [Profile] = []
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for entry in entries {
            let name = entry.lastPathComponent
            // "<name>.lock" dirs are Claude Code's transient refresh locks, not profiles.
            guard !name.hasPrefix("."), !name.hasSuffix(".lock"),
                  (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            // Build from `root` (not the enumerated URL, which may have symlinks resolved)
            // so the hash matches the CLAUDE_CONFIG_DIR string claude-profile exports.
            let dir = root.appendingPathComponent(name)
            let account = readAccount(dir.appendingPathComponent(".claude.json"))
            profiles.append(Profile(
                id: name,
                configDir: dir,
                email: account?.email,
                organization: account?.organization,
                keychainService: keychainService(forConfigDir: dir.path),
                isDefault: name == defaultName
            ))
        }
        profiles.sort { a, b in
            if a.isDefault != b.isDefault { return a.isDefault }
            return a.id < b.id
        }

        // The plain ~/.claude login is only shown when it is an account no profile already covers.
        if let account = readAccount(home.appendingPathComponent(".claude.json")),
           let email = account.email,
           !profiles.contains(where: { $0.email == email }) {
            profiles.append(Profile(
                id: plainProfileID,
                configDir: home.appendingPathComponent(".claude"),
                email: email,
                organization: account.organization,
                keychainService: plainServiceName,
                isDefault: false
            ))
        }
        return profiles
    }

    private static func readAccount(_ url: URL) -> (email: String?, organization: String?)? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = obj["oauthAccount"] as? [String: Any] else { return nil }
        return (account["emailAddress"] as? String, account["organizationName"] as? String)
    }
}
