// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacTweaks",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MacTweaks", path: "Sources/MacTweaks")
    ]
)
