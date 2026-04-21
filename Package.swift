// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "keyspace",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "keyspace"
        ),
        .testTarget(
            name: "keyspaceTests",
            dependencies: ["keyspace"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
