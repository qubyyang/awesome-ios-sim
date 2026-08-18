import Foundation
import SimctlDriver
import SimulatorStateCore

if CommandLine.arguments.dropFirst().first == "--version" {
    print(AwesomeIOSSim.version)
} else {
    let server = MCPServer(toolHandler: SimulatorToolService(controller: SimctlClient()))
    while let line = readLine(strippingNewline: true) {
        guard let response = server.handle(line: Data(line.utf8)) else { continue }
        FileHandle.standardOutput.write(response)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
