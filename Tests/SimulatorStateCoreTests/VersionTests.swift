import Testing
@testable import SimulatorStateCore

@Test func versionIsDefined() {
    #expect(!AwesomeIOSSim.version.isEmpty)
}
