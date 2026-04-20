// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "keysmith",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "keysmith"
        ),
        .testTarget(
            name: "keysmithTests",
            dependencies: ["keysmith"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
