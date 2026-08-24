// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FaderLabCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FaderLabCore",
            targets: ["FaderLabCore"]
        )
    ],
    targets: [
        .target(
            name: "FaderLabCore"
        ),
        .testTarget(
            name: "FaderLabCoreTests",
            dependencies: ["FaderLabCore"]
        )
    ]
)
