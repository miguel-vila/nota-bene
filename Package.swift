// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotaBene",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "NotaBene", targets: ["NotaBene"]),
    ],
    dependencies: [
        // Used only by EvalSampleWriter (gated on `#if EVAL_CAPTURE`). Linked
        // into the package but the symbols are dead-stripped in Release builds
        // since no `#if EVAL_CAPTURE` block references them outside Debug.
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "NotaBene",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Sources/NotaBene",
            swiftSettings: [
                // EVAL_CAPTURE is auto-on in Debug builds (Xcode's Debug
                // config, `swift build`, `swift test`) and auto-off in Release
                // (Xcode's Release config, `swift build -c release`, archive).
                // No manual Xcode setting required — see docs/eval-capture.md.
                .define("EVAL_CAPTURE", .when(configuration: .debug)),
            ]
        ),
        .testTarget(
            name: "NotaBeneTests",
            dependencies: ["NotaBene"],
            path: "Tests/NotaBeneTests"
        ),
    ]
)
