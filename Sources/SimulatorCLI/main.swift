import SimulatorStateCore

if CommandLine.arguments.dropFirst().first == "--version" {
    print(AwesomeIOSSim.version)
} else {
    print("ios-sim-state \(AwesomeIOSSim.version)")
    print("Run with --help for usage. Simulator State as Code commands are being initialized.")
}

