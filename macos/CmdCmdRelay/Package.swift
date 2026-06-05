// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CmdCmdRelay",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CmdCmdRelayApp", targets: ["CmdCmdRelayApp"])
    ],
    targets: [
        .executableTarget(
            name: "CmdCmdRelayApp",
            path: "Sources/CmdCmdRelayApp"
        )
    ]
)
