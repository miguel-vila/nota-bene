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
            path: "Sources/NotaBene"
        ),
        .testTarget(
            name: "NotaBeneTests",
            dependencies: ["NotaBene"],
            path: "Tests/NotaBeneTests"
        ),
    ]
)
