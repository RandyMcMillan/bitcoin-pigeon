// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RustyLib",
    platforms: [
        .macOS(.v15),
        .iOS(.v15),
        .macCatalyst(.v15)
    ],
    products: [
        .library(
            name: "RustyLib",
            targets: ["RustyLib"])
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "RustyLib",
            dependencies: [
                .byName(name: "RustyCore")
            ],
            path: "Sources/"
        ),
        .testTarget(
            name: "RustyLibTests",
            dependencies: ["RustyLib"],
            path: "Tests"
        ),
        .binaryTarget(
            name: "RustyCore",
            path: "artifacts/RustyCore.xcframework"
        ),
    ]
)
