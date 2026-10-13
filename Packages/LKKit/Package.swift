// swift-tools-version: 6.0
import PackageDescription

// Every module of the app except the app and extension targets themselves.
// Dependencies run one way: Core <- Model <- feature modules <- app/extension.
// The widget extension links Core, Model, DesignSystem and LiveActivity, so those stay
// extension-safe: no UIKit-only APIs, no networking.
// Modules arrive with their milestone (SPEC.md §5.2); M0 has the foundations plus the minimal
// Live Activity plumbing the APNs-from-Worker spike needs.
let package = Package(
    name: "LKKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "Core", targets: ["Core"]),
        .library(name: "Model", targets: ["Model"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "LiveActivity", targets: ["LiveActivity"]),
    ],
    targets: [
        .target(name: "Core"),
        .target(name: "Model", dependencies: ["Core"]),
        .target(name: "DesignSystem", dependencies: ["Core"]),
        // ActivityKit's async sequences hand back values that predate strict concurrency
        // checking; this module stays in Swift 5 mode until the framework is annotated.
        .target(
            name: "LiveActivity",
            dependencies: ["Core", "Model", "DesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .testTarget(name: "CoreTests", dependencies: ["Core"]),
        .testTarget(name: "ModelTests", dependencies: ["Model"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
        .testTarget(name: "LiveActivityTests", dependencies: ["LiveActivity", "Model"]),
    ]
)
