// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AwesomeIOSSim",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "SimulatorStateCore", targets: ["SimulatorStateCore"]),
        .library(name: "SimctlDriver", targets: ["SimctlDriver"]),
        .executable(name: "ios-sim-state", targets: ["SimulatorCLI"]),
        .executable(name: "ios-sim-state-mcp", targets: ["SimulatorMCP"]),
    ],
    targets: [
        .target(name: "SimulatorStateCore"),
        .target(
            name: "SimctlDriver",
            dependencies: ["SimulatorStateCore"]
        ),
        .executableTarget(
            name: "SimulatorCLI",
            dependencies: ["SimulatorStateCore", "SimctlDriver"]
        ),
        .executableTarget(
            name: "SimulatorMCP",
            dependencies: ["SimulatorStateCore", "SimctlDriver"]
        ),
        .testTarget(
            name: "SimulatorStateCoreTests",
            dependencies: ["SimulatorStateCore"]
        ),
        .testTarget(
            name: "SimctlDriverTests",
            dependencies: ["SimctlDriver"]
        ),
        .testTarget(
            name: "SimulatorMCPTests",
            dependencies: ["SimulatorMCP"]
        ),
    ]
)

