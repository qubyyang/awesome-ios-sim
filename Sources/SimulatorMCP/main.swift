import Foundation
import SimulatorStateCore

if CommandLine.arguments.dropFirst().first == "--version" {
    print(AwesomeIOSSim.version)
} else {
    FileHandle.standardError.write(
        Data("ios-sim-state-mcp \(AwesomeIOSSim.version)\n".utf8)
    )
}
