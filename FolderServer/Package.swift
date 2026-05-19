// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ServerList",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "ServerList",
            dependencies: [],
            path: "Sources"
        )
    ]
)