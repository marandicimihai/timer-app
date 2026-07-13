// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MinimalTimer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MinimalTimer", targets: ["MinimalTimer"])
    ],
    targets: [
        .executableTarget(name: "MinimalTimer"),
        .testTarget(name: "MinimalTimerTests", dependencies: ["MinimalTimer"])
    ]
)

