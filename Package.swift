// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ListenIELTS",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ListenIELTS",
            path: "Sources",
            resources: []
        )
    ]
)
