import Foundation
import UsageCore

let usageText = """
usage: claude-usage [--json] [--no-refresh] [--watch [seconds]] [--demo]

Shows plan usage limits for every claude-profile account.

  --json         machine-readable output
  --no-refresh   never refresh expired tokens (read-only Keychain access)
  --watch [s]    redraw every s seconds (default 60)
  --demo         show fictional sample accounts (no Keychain access)
  -h, --help     show this help

"""

var asJSON = false
var allowRefresh = true
var watchInterval: Double? = nil
var demo = false

var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--json": asJSON = true
    case "--no-refresh": allowRefresh = false
    case "--demo": demo = true
    case "--watch":
        if let next = args.first, let secs = Double(next), secs > 0 {
            args.removeFirst()
            watchInterval = secs
        } else {
            watchInterval = 60
        }
    case "-h", "--help":
        print(usageText, terminator: "")
        exit(0)
    default:
        FileHandle.standardError.write(Data("claude-usage: unknown option '\(arg)'\n\(usageText)".utf8))
        exit(2)
    }
}

let useColor = isatty(STDOUT_FILENO) == 1 && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
let service = UsageService(keychain: SecurityCLIKeychain(), http: URLSessionTransport(), allowRefresh: allowRefresh)

@MainActor
func render() async {
    let now = Date()
    let profiles = demo ? [] : ProfileDiscovery.discover()
    let rows = demo ? DemoData.accounts(now: now).map(\.usage) : await service.fetchAll(profiles)
    if asJSON {
        if let data = try? TableRenderer.json(rows, now: now) {
            FileHandle.standardOutput.write(data)
            print("")
        }
    } else if rows.isEmpty {
        print("No profiles found in \(ProfileDiscovery.defaultRoot.path)")
    } else {
        print(TableRenderer.table(rows, now: now, color: useColor), terminator: "")
    }
}

if let interval = watchInterval {
    while true {
        print("\u{1B}[2J\u{1B}[H", terminator: "")
        await render()
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("\nUpdated \(stamp) · every \(Int(interval))s · Ctrl-C to quit")
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
    }
} else {
    await render()
}
