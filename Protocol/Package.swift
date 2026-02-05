// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ISCSIProtocol",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ISCSIProtocol",
            targets: ["ISCSIProtocol"]
        ),
        .library(
            name: "ISCSINetwork",
            targets: ["ISCSINetwork"]
        )
    ],
    targets: [
        .target(
            name: "ISCSIProtocol",
            dependencies: [],
            path: "Sources/Protocol"
        ),
        .target(
            name: "ISCSINetwork",
            dependencies: ["ISCSIProtocol"],
            path: "Sources/Network"
        ),
        .testTarget(
            name: "ISCSIProtocolTests",
            dependencies: ["ISCSIProtocol"],
            path: "Tests/ProtocolTests"
        ),
        .testTarget(
            name: "ISCSINetworkTests",
            dependencies: ["ISCSINetwork"],
            path: "Tests/NetworkTests"
        )
    ]
)
