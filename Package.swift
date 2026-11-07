// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EdgeSwipe",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "EdgeSwipe", targets: ["EdgeSwipe"])],
    targets: [
        .binaryTarget(name: "Sparkle", path: "Vendor/Sparkle.xcframework"),
        .target(name: "GestureCore"),
        .target(name: "MTLayout"),
        .target(name: "PrivateMac", dependencies: ["MTLayout"]),
        .executableTarget(name: "EdgeSwipe", dependencies: ["GestureCore", "PrivateMac", "Sparkle"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])])
    ]
)
