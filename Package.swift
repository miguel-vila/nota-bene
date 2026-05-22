// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotaBene",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "NotaBene", targets: ["NotaBene"]),
    ],
    targets: [
        .target(
            name: "NotaBene",
            path: "Sources/NotaBene"
        ),
        .testTarget(
            name: "NotaBeneTests",
            dependencies: ["NotaBene"],
            path: "Tests/NotaBeneTests"
        ),
    ]
)
