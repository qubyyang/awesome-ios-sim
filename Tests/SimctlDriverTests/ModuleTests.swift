import Testing
@testable import SimctlDriver

@Test func moduleVersionIsDefined() {
    #expect(!SimctlDriverModule.version.isEmpty)
}
