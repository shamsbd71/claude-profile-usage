// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeProfileUsage",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UsageCore", targets: ["UsageCore"]),
        .executable(name: "claude-usage", targets: ["claude-usage"]),
        .executable(name: "ClaudeProfileUsage", targets: ["ClaudeProfileUsage"]),
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "claude-usage", dependencies: ["UsageCore"]),
        .target(name: "UsageWidgetViews", dependencies: ["UsageCore"]),
        .executableTarget(name: "ClaudeProfileUsage", dependencies: ["UsageCore", "UsageWidgetViews"]),
        // Packaged by scripts/bundle.sh as ClaudeProfileUsage.app/Contents/PlugIns/ClaudeProfileUsageWidget.appex
        .executableTarget(name: "ClaudeProfileUsageWidget", dependencies: ["UsageCore", "UsageWidgetViews"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"], resources: [.copy("Fixtures")]),
    ]
)
