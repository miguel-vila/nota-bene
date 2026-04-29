// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ReadwiseHighlighter",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "ReadwiseHighlighter", targets: ["ReadwiseHighlighter"]),
    ],
    targets: [
        .target(
            name: "ReadwiseHighlighter",
            path: "Sources/ReadwiseHighlighter"
        ),
        .testTarget(
            name: "ReadwiseHighlighterTests",
            dependencies: ["ReadwiseHighlighter"],
            path: "Tests/ReadwiseHighlighterTests"
        ),
    ]
)
