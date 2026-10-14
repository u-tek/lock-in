// swift-tools-version: 6.0
import PackageDescription

// Every module of the app except the app and extension targets themselves.
// Dependencies run one way: Core <- Model <- feature modules <- app/extension.
// The widget extension links Core, Model, DesignSystem, Creature and LiveActivity, so those stay
// extension-safe: no UIKit-only APIs, no networking.
// Modules arrive with their milestone (SPEC.md §5.2).
let package = Package(
    name: "LKKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Model", targets: ["Model"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Creature", targets: ["Creature"]),
        .library(name: "LiveActivity", targets: ["LiveActivity"]),
        .library(name: "SessionEngine", targets: ["SessionEngine"]),
        .library(name: "Paywall", targets: ["Paywall"]),
        .library(name: "API", targets: ["API"]),
        .library(name: "Social", targets: ["Social"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Model", dependencies: ["Core"]),
        .target(name: "DesignSystem", dependencies: ["Core"]),
        // The Lockling, drawn in SwiftUI shapes. The widget extension links it, so it stays
        // extension-safe: no UIApplication, no network, no bitmap assets.
        .target(name: "Creature", dependencies: ["Core", "Model", "DesignSystem"]),
        // ActivityKit's async sequences hand back values that predate strict concurrency
        // checking; this module stays in Swift 5 mode until the framework is annotated.
        .target(
            name: "LiveActivity",
            dependencies: ["Core", "Model", "DesignSystem", "Creature"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The local session: timer state, persistence, coins and streaks, and the Live Activity
        // that mirrors it. App only. Swift 5 mode for the same ActivityKit reason as above.
        .target(
            name: "SessionEngine",
            dependencies: ["Core", "Model", "LiveActivity"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Lockin Plus: plans, entitlements and the purchase flow, on StoreKit 2. App only.
        .target(name: "Paywall", dependencies: ["Core", "Model", "DesignSystem", "Creature"]),
        // The Lockin API: REST client, the session token in the Keychain, and the JSON models.
        // App only (the widget extension has no network).
        .target(name: "API", dependencies: ["Core", "Model"]),
        // Accounts and friends: Sign in with Apple, handles, friend codes and QR, block and report.
        .target(name: "Social", dependencies: ["Core", "Model", "API"]),

        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ModelTests", dependencies: ["Model"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "CreatureTests", dependencies: ["Creature", "Model"]),
        .testTarget(name: "LiveActivityTests", dependencies: ["LiveActivity", "Model"]),
        .testTarget(name: "SessionEngineTests", dependencies: ["SessionEngine", "Core", "Model", "LiveActivity"]),
        .testTarget(name: "PaywallTests", dependencies: ["Paywall", "Creature", "Model"]),
        .testTarget(name: "APITests", dependencies: ["API", "Core", "Model"]),
        .testTarget(name: "SocialTests", dependencies: ["Social", "API", "Core", "Model"]),
    ]
)
