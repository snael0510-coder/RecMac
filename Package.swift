// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RecMac",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(name: "RecMac", path: "Sources/RecMac")
    ]
)
