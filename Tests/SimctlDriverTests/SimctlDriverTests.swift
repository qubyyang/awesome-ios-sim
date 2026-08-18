import Foundation
import Testing
import SimulatorStateCore
@testable import SimctlDriver

private let listFixture = #"""
{
  "runtimes": [{
    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
    "name": "iOS 27.0",
    "version": "27.0",
    "isAvailable": true
  }],
  "devices": {
    "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [{
      "udid": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
      "name": "iPhone 17 Pro",
      "state": "Shutdown",
      "isAvailable": true,
      "dataPath": "/tmp/device"
    }]
  }
}
"""#

private let appsFixture = #"""
{
  "com.example.app": {
    "CFBundleIdentifier": "com.example.app",
    "BundlePath": "/tmp/Example.app"
  }
}
"""#

@Test func parsesInventoryAndApplications() throws {
    let executor = StubExecutor { arguments in
        if arguments == ["simctl", "list", "--json"] {
            return .success(arguments, listFixture)
        }
        if arguments == ["simctl", "listapps", "--json", "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"] {
            return .success(arguments, appsFixture)
        }
        return .failure(arguments, "unexpected command")
    }
    let client = SimctlClient(executor: executor, environment: ["DEVELOPER_DIR": "/Applications/Xcode.app"])

    let inventory = try client.inventory()
    #expect(inventory.devices.count == 1)
    #expect(inventory.devices[0].runtimeIdentifier == "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
    #expect(inventory.developerDirectory == "/Applications/Xcode.app")

    let snapshot = try client.snapshot(udid: inventory.devices[0].udid)
    #expect(snapshot.state.applications.map(\.bundleIdentifier) == ["com.example.app"])
    #expect(snapshot.state.power == .shutdown)
}

@Test func mapsPreferenceWithoutShellInterpolation() throws {
    let executor = StubExecutor { arguments in .success(arguments) }
    let client = SimctlClient(executor: executor)
    let operation = SimulatorOperation(
        id: "001-setPreference",
        action: .setPreference,
        targetUDID: "DEVICE",
        arguments: [
            "domain": .string("com.example.app"),
            "key": .string("greeting"),
            "value": .string("hello; rm -rf /"),
        ],
        risk: .reversible,
        requiresConfirmation: true,
        reason: "test"
    )

    let receipt = try client.execute(operation)
    #expect(receipt.commands == [[
        "xcrun", "simctl", "spawn", "DEVICE", "defaults", "write",
        "com.example.app", "greeting", "-string", "hello; rm -rf /",
    ]])
}

@Test func bootWaitsUntilSimulatorIsReady() throws {
    let executor = StubExecutor { arguments in .success(arguments) }
    let client = SimctlClient(executor: executor)
    let operation = SimulatorOperation(
        id: "001-boot",
        action: .boot,
        targetUDID: "DEVICE",
        risk: .reversible,
        requiresConfirmation: true,
        reason: "test"
    )

    let receipt = try client.execute(operation)
    #expect(receipt.commands == [
        ["xcrun", "simctl", "boot", "DEVICE"],
        ["xcrun", "simctl", "bootstatus", "DEVICE", "-b"],
    ])
}

@Test func applyDefaultsToDryRunAndStopsOnFailure() throws {
    let controller = StubController(exitCodes: [0, 7, 0])
    let applier = SimulatorPlanApplier(controller: controller)
    let operations = (1...3).map { index in
        SimulatorOperation(
            id: "00\(index)-boot",
            action: .boot,
            targetUDID: "DEVICE",
            risk: .reversible,
            requiresConfirmation: true,
            reason: "test"
        )
    }
    let plan = SimulatorStatePlan(
        profileName: "test",
        targetUDID: "DEVICE",
        diff: [],
        operations: operations
    )

    let dryRun = try applier.apply(plan, confirmed: false)
    #expect(dryRun.status == .dryRun)
    #expect(controller.executionCount == 0)

    let applied = try applier.apply(plan, confirmed: true)
    #expect(applied.status == .failed)
    #expect(applied.receipts.count == 2)
    #expect(controller.executionCount == 2)
}

private final class StubExecutor: CommandExecuting, @unchecked Sendable {
    private let handler: ([String]) -> CommandResult

    init(handler: @escaping ([String]) -> CommandResult) {
        self.handler = handler
    }

    func run(executable: String, arguments: [String]) throws -> CommandResult {
        handler(arguments)
    }
}

private extension CommandResult {
    static func success(_ arguments: [String], _ output: String = "") -> CommandResult {
        CommandResult(executable: SimctlClient.xcrunPath, arguments: arguments, exitCode: 0, standardOutput: output)
    }

    static func failure(_ arguments: [String], _ error: String) -> CommandResult {
        CommandResult(executable: SimctlClient.xcrunPath, arguments: arguments, exitCode: 1, standardError: error)
    }
}

private final class StubController: SimulatorControlling, @unchecked Sendable {
    private let exitCodes: [Int32]
    private let lock = NSLock()
    private var count = 0

    init(exitCodes: [Int32]) {
        self.exitCodes = exitCodes
    }

    var executionCount: Int {
        lock.withLock { count }
    }

    func inventory() throws -> SimulatorInventory {
        SimulatorInventory(runtimes: [], devices: [])
    }

    func snapshot(udid: String) throws -> SimulatorSnapshot {
        throw SimctlDriverError.deviceNotFound(udid)
    }

    func execute(_ operation: SimulatorOperation) throws -> OperationReceipt {
        let code = lock.withLock { () -> Int32 in
            let code = exitCodes[count]
            count += 1
            return code
        }
        return OperationReceipt(
            operationID: operation.id,
            action: operation.action,
            targetUDID: operation.targetUDID,
            commands: [],
            exitCode: code,
            standardOutput: "",
            standardError: code == 0 ? "" : "failed",
            startedAt: "start",
            finishedAt: "finish"
        )
    }
}
