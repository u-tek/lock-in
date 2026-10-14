// swift-tools-version: 6.0
import PackageDescription

// Every module of the app except the app and extension targets themselves.
// Dependencies run one way: Core <- Model <- feature modules <- app/extension.
// The widget extension links Core, Model, DesignSystem, Creature, LiveActivity and WidgetViews,
// so those stay extension-safe: no UIKit-only APIs, no networking.
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
        .library(name: "DeepFocus", targets: ["DeepFocus"]),
        .library(name: "Notifications", targets: ["Notifications"]),
        .library(name: "WidgetViews", targets: ["WidgetViews"]),
        .library(name: "ShareCards", targets: ["ShareCards"]),
    ],
    dependencies: [
        // Lockin Plus's purchases (M7): RevenueCat's SDK, behind `PlusStore`, used only when the
        // build has a RevenueCat key (LK_REVENUECAT_KEY). Paywall is the only module that links it.
        .package(url: "https://github.com/RevenueCat/purchases-ios-spm", from: "5.92.0"),
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
            dependencies: ["Core", "Model", "LiveActivity", "API"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Lockin Plus: plans, entitlements and the purchase flow, through RevenueCat when the
        // build has its key, on StoreKit 2 when it doesn't (M7). App only.
        .target(
            name: "Paywall",
            dependencies: [
                "Core", "Model", "DesignSystem", "Creature",
                .product(name: "RevenueCat", package: "purchases-ios-spm"),
            ]
        ),
        // The Lockin API: REST client, the session token in the Keychain, and the JSON models.
        // App only (the widget extension has no network).
        .target(name: "API", dependencies: ["Core", "Model"]),
        // Accounts and friends: Sign in with Apple, handles, friend codes and QR, block and report.
        .target(name: "Social", dependencies: ["Core", "Model", "API"]),
        // Deep Focus (M8, Plus): the app picker, shields during sessions and slips. Linked by the app
        // and the three Screen Time extensions, so it stays extension-safe.
        .target(
            name: "DeepFocus",
            dependencies: ["Core", "Model", "DesignSystem", "Creature"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Notifications (M4): the "is locking in" alert's category and actions, reading its
        // payload, quiet hours, and what a tap on it should do. App only; no session engine, so
        // it stays a set of plain values the tests can pin down.
        .target(name: "Notifications", dependencies: ["Core", "Model"]),
        // The Home and Lock Screen widgets' views (M6): linked by the widget extension, which
        // draws them, and by the app, whose snapshots draw the same. Extension-safe: no
        // UIApplication, no network. LiveActivity for the Lock in button's `StartSessionIntent`.
        .target(name: "WidgetViews", dependencies: ["Core", "Model", "DesignSystem", "Creature", "LiveActivity"]),
        // Share cards (M6): the 9:16 and 1:1 pictures of a finished session, drawn in SwiftUI and
        // rendered with ImageRenderer. App only.
        .target(name: "ShareCards", dependencies: ["Core", "Model", "DesignSystem", "Creature"]),

        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ModelTests", dependencies: ["Model"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "CreatureTests", dependencies: ["Creature", "Model"]),
        .testTarget(name: "LiveActivityTests", dependencies: ["LiveActivity", "Model"]),
        .testTarget(name: "SessionEngineTests", dependencies: ["SessionEngine", "Core", "Model", "LiveActivity", "API"]),
        .testTarget(
            name: "PaywallTests",
            dependencies: ["Paywall", "Core", "Creature", "Model", .product(name: "RevenueCat", package: "purchases-ios-spm")]
        ),
        .testTarget(name: "APITests", dependencies: ["API", "Core", "Model"]),
        .testTarget(name: "SocialTests", dependencies: ["Social", "API", "Core", "Model"]),
        .testTarget(name: "DeepFocusTests", dependencies: ["DeepFocus", "Core", "Model"]),
        .testTarget(name: "NotificationsTests", dependencies: ["Notifications", "Core", "Model"]),
        .testTarget(name: "WidgetViewsTests", dependencies: ["WidgetViews", "Model"]),
        .testTarget(name: "ShareCardsTests", dependencies: ["ShareCards", "Model"]),
    ]
)
