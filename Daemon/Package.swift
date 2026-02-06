// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ISCSIDaemon",
    platforms: [
        .macOS(.v15)  // Requires macOS 15+ for DriverKit
    ],
    products: [
        .executable(
            name: "iscsid",
            targets: ["ISCSIDaemon"]
        )
    ],
    dependencies: [
        // Depend on the Protocol layer
        .package(path: "../Protocol")
    ],
    targets: [
        .executableTarget(
            name: "ISCSIDaemon",
            dependencies: [
                .product(name: "ISCSIProtocol", package: "Protocol"),
                .product(name: "ISCSINetwork", package: "Protocol")
            ],
            path: ".",
            sources: [
                "ISCSIDaemon.swift",
                "DextConnector.swift",
                "Bridge/DextTypes.swift"
            ]
        ),
        .testTarget(
            name: "DaemonTests",
            dependencies: ["ISCSIDaemon"],
            path: "Tests/DaemonTests"
        )
    ]
)
