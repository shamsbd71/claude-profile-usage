import Foundation

public enum Endpoints {
    public static let usage = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let token = URL(string: "https://platform.claude.com/v1/oauth/token")!
    /// Claude Code's public OAuth client id (taken from Claude Code 2.1.310).
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let betaHeader = "oauth-2025-04-20"
    public static let userAgent = "claude-profile-usage/1.0"
}
