// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EdgeSwipe",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "EdgeSwipe", targets: ["EdgeSwipe"])],
    targets: [
        .target(name: "GestureCore"),
        .target(name: "MTLayout"),
        .target(name: "PrivateMac", dependencies: ["MTLayout"]),
        .executableTarget(name: "EdgeSwipe", dependencies: ["GestureCore", "PrivateMac"])
    ]
)
