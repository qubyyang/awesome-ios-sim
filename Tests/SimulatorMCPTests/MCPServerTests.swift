import Foundation
import Testing
import SimctlDriver
import SimulatorStateCore
@testable import SimulatorMCP

@Test func currentDiscoveryIsStatelessAndAdvertisesTools() throws {
    let server = MCPServer(toolHandler: NoopToolHandler())
    let response = try send(server, method: "server/discover", params: currentParams())
    let result = try object(response["result"])

    #expect(result["resultType"] == .string("complete"))
    #expect(result["supportedVersions"] == .array([.string("2026-07-28")]))
    #expect(try object(result["capabilities"])["tools"] != nil)
    #expect(try object(result["_meta"])["io.modelcontextprotocol/serverInfo"] != nil)
}

@Test func currentToolsListWorksWithoutInitialize() throws {
    let server = MCPServer(toolHandler: NoopToolHandler())
    let response = try send(server, method: "tools/list", params: currentParams())
    let result = try object(response["result"])
    let tools = try array(result["tools"])

    #expect(result["resultType"] == .string("complete"))
    #expect(tools.count == 1)
    #expect(try object(tools[0])["name"] == .string("test_tool"))
}

@Test func currentRequestsRejectMissingMetadata() throws {
    let server = MCPServer(toolHandler: NoopToolHandler())
    let response = try send(server, method: "tools/list", params: [:])
    let error = try object(response["error"])

    #expect(error["code"] == .integer(-32602))
}

@Test func legacyInitializeEnablesHandshakeEraRequests() throws {
    let server = MCPServer(toolHandler: NoopToolHandler())
    let initialize = try send(server, method: "initialize", params: [
        "protocolVersion": .string("2025-11-25"),
        "capabilities": .object([:]),
        "clientInfo": .object(["name": .string("test"), "version": .string("1")]),
    ])
    #expect(try object(initialize["result"])["protocolVersion"] == .string("2025-11-25"))

    let list = try send(server, method: "tools/list", params: [:], id: .integer(2))
    let result = try object(list["result"])
    #expect(result["tools"] != nil)
    #expect(result["resultType"] == nil)
}

@Test func simulatorApplyDefaultsToDryRunAndRequiresExplicitTrue() throws {
    let controller = MCPStubController()
    let service = SimulatorToolService(controller: controller)
    let server = MCPServer(toolHandler: service)
    let operation = SimulatorOperation(
        id: "001-boot",
        action: .boot,
        targetUDID: "DEVICE",
        risk: .reversible,
        requiresConfirmation: true,
        reason: "test"
    )
    let plan = SimulatorStatePlan(
        profileName: "test",
        targetUDID: "DEVICE",
        diff: [],
        operations: [operation]
    )
    let planValue = try encodedValue(plan)

    let dryRunParams = currentParams(merging: [
        "name": .string("simulator_apply"),
        "arguments": .object(["plan": planValue]),
    ])
    let dryRun = try send(server, method: "tools/call", params: dryRunParams)
    let dryRunResult = try object(dryRun["result"])
    #expect(dryRunResult["isError"] == .bool(false))
    #expect(try object(dryRunResult["structuredContent"])["status"] == .string("dryRun"))
    #expect(controller.executionCount == 0)

    let applyParams = currentParams(merging: [
        "name": .string("simulator_apply"),
        "arguments": .object(["plan": planValue, "confirm": .bool(true)]),
    ])
    let applied = try send(server, method: "tools/call", params: applyParams, id: .integer(2))
    let appliedResult = try object(applied["result"])
    #expect(try object(appliedResult["structuredContent"])["status"] == .string("succeeded"))
    #expect(controller.executionCount == 1)
}

private func currentParams(
    merging values: [String: JSONValue] = [:]
) -> [String: JSONValue] {
    var result = values
    result["_meta"] = .object([
        "io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
        "io.modelcontextprotocol/clientInfo": .object([
            "name": .string("tests"),
            "version": .string("1.0"),
        ]),
        "io.modelcontextprotocol/clientCapabilities": .object([:]),
    ])
    return result
}

private func send(
    _ server: MCPServer,
    method: String,
    params: [String: JSONValue],
    id: JSONValue = .integer(1)
) throws -> [String: JSONValue] {
    let request: JSONValue = .object([
        "jsonrpc": .string("2.0"),
        "id": id,
        "method": .string(method),
        "params": .object(params),
    ])
    let data = try StateCodec.encode(request, pretty: false)
    let responseData = try #require(server.handle(line: data))
    return try object(try JSONDecoder().decode(JSONValue.self, from: responseData))
}

private func object(_ value: JSONValue?) throws -> [String: JSONValue] {
    guard case let .object(object)? = value else {
        throw MCPProtocolError.invalidParams("Expected object in test response")
    }
    return object
}

private func array(_ value: JSONValue?) throws -> [JSONValue] {
    guard case let .array(array)? = value else {
        throw MCPProtocolError.invalidParams("Expected array in test response")
    }
    return array
}

private func encodedValue<T: Encodable>(_ value: T) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: StateCodec.encode(value, pretty: false))
}

private struct NoopToolHandler: MCPToolHandling {
    let tools: [MCPToolDefinition] = [
        .init(
            name: "test_tool",
            title: "Test",
            description: "Test tool",
            inputSchema: .object(["type": .string("object")]),
            outputSchema: .object(["type": .string("object")]),
            annotations: .object(["readOnlyHint": .bool(true)])
        ),
    ]

    func call(name: String, arguments: [String: JSONValue]) -> MCPToolInvocationResult {
        .init(text: "ok", structuredContent: .object(["ok": .bool(true)]), isError: false)
    }
}

private final class MCPStubController: SimulatorControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var executionCount: Int { lock.withLock { count } }

    func inventory() throws -> SimulatorInventory {
        SimulatorInventory(runtimes: [], devices: [])
    }

    func snapshot(udid: String) throws -> SimulatorSnapshot {
        throw SimctlDriverError.deviceNotFound(udid)
    }

    func execute(_ operation: SimulatorOperation) throws -> OperationReceipt {
        lock.withLock { count += 1 }
        return OperationReceipt(
            operationID: operation.id,
            action: operation.action,
            targetUDID: operation.targetUDID,
            commands: [],
            exitCode: 0,
            standardOutput: "",
            standardError: "",
            startedAt: "start",
            finishedAt: "finish"
        )
    }
}
