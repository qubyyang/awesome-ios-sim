import Foundation
import SimulatorStateCore

final class MCPServer {
    static let currentVersion = "2026-07-28"
    static let legacyVersions = ["2025-11-25", "2025-06-18", "2024-11-05"]
    static let serverName = "awesome-ios-sim"

    private let toolHandler: any MCPToolHandling
    private var legacyNegotiatedVersion: String?

    init(toolHandler: any MCPToolHandling) {
        self.toolHandler = toolHandler
    }

    func handle(line: Data) -> Data? {
        let request: JSONRPCRequest
        do {
            request = try JSONDecoder().decode(JSONRPCRequest.self, from: line)
        } catch {
            return encode(errorResponse(id: .null, code: -32700, message: "Parse error", data: nil))
        }

        guard request.jsonrpc == "2.0" else {
            return encode(errorResponse(id: request.id ?? .null, code: -32600, message: "Invalid Request", data: nil))
        }

        if request.id == nil {
            handleNotification(request)
            return nil
        }

        do {
            let result = try dispatch(request)
            return encode(.object([
                "jsonrpc": .string("2.0"),
                "id": request.id!,
                "result": result,
            ]))
        } catch let error as MCPProtocolError {
            return encode(errorResponse(
                id: request.id!,
                code: error.code,
                message: error.message,
                data: error.data
            ))
        } catch {
            return encode(errorResponse(
                id: request.id!,
                code: -32603,
                message: "Internal error",
                data: .string(error.localizedDescription)
            ))
        }
    }

    private func dispatch(_ request: JSONRPCRequest) throws -> JSONValue {
        if request.method == "initialize" {
            return try initialize(request)
        }

        let era = try protocolEra(for: request)
        switch request.method {
        case "server/discover":
            guard era == .current else { throw MCPProtocolError.methodNotFound(request.method) }
            return discoverResult()
        case "ping":
            return complete([:], era: era)
        case "tools/list":
            return try toolsListResult(era: era)
        case "tools/call":
            return try toolsCallResult(request: request, era: era)
        default:
            throw MCPProtocolError.methodNotFound(request.method)
        }
    }

    private func initialize(_ request: JSONRPCRequest) throws -> JSONValue {
        guard let requested = request.params?["protocolVersion"]?.stringValue else {
            throw MCPProtocolError.invalidParams("initialize requires protocolVersion")
        }
        let negotiated = Self.legacyVersions.contains(requested)
            ? requested
            : Self.legacyVersions[0]
        legacyNegotiatedVersion = negotiated
        return .object([
            "protocolVersion": .string(negotiated),
            "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
            "serverInfo": serverInfo,
            "instructions": .string(instructions),
        ])
    }

    private func protocolEra(for request: JSONRPCRequest) throws -> MCPProtocolEra {
        if let metadata = request.params?["_meta"], case let .object(meta) = metadata {
            guard let version = meta["io.modelcontextprotocol/protocolVersion"]?.stringValue else {
                throw MCPProtocolError.invalidParams("_meta is missing io.modelcontextprotocol/protocolVersion")
            }
            guard version == Self.currentVersion else {
                throw MCPProtocolError(
                    code: -32022,
                    message: "Unsupported protocol version: \(version)",
                    data: .object([
                        "supportedVersions": .array(
                            ([Self.currentVersion] + Self.legacyVersions).map(JSONValue.string)
                        ),
                    ])
                )
            }
            guard case .object? = meta["io.modelcontextprotocol/clientCapabilities"] else {
                throw MCPProtocolError.invalidParams(
                    "_meta is missing io.modelcontextprotocol/clientCapabilities"
                )
            }
            return .current
        }
        if let version = legacyNegotiatedVersion {
            return .legacy(version)
        }
        throw MCPProtocolError.invalidParams(
            "Current requests require per-request _meta; legacy clients must initialize first"
        )
    }

    private func discoverResult() -> JSONValue {
        complete([
            "supportedVersions": .array([.string(Self.currentVersion)]),
            "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
            "instructions": .string(instructions),
            "ttlMs": .integer(3_600_000),
            "cacheScope": .string("public"),
        ], era: .current)
    }

    private func toolsListResult(era: MCPProtocolEra) throws -> JSONValue {
        let tools = try toolHandler.tools.map { try encodeValue($0) }
        var fields: [String: JSONValue] = ["tools": .array(tools)]
        if era == .current {
            fields["ttlMs"] = .integer(300_000)
            fields["cacheScope"] = .string("public")
        }
        return complete(fields, era: era)
    }

    private func toolsCallResult(request: JSONRPCRequest, era: MCPProtocolEra) throws -> JSONValue {
        guard let name = request.params?["name"]?.stringValue else {
            throw MCPProtocolError.invalidParams("tools/call requires name")
        }
        let arguments: [String: JSONValue]
        switch request.params?["arguments"] {
        case let .object(value): arguments = value
        case nil: arguments = [:]
        default: throw MCPProtocolError.invalidParams("tools/call arguments must be an object")
        }
        guard toolHandler.tools.contains(where: { $0.name == name }) else {
            throw MCPProtocolError.invalidParams("Unknown tool: \(name)")
        }

        let invocation = toolHandler.call(name: name, arguments: arguments)
        return complete([
            "content": .array([.object([
                "type": .string("text"),
                "text": .string(invocation.text),
            ])]),
            "structuredContent": invocation.structuredContent,
            "isError": .bool(invocation.isError),
        ], era: era)
    }

    private func complete(_ fields: [String: JSONValue], era: MCPProtocolEra) -> JSONValue {
        var result = fields
        if era == .current {
            result["resultType"] = .string("complete")
            result["_meta"] = .object([
                "io.modelcontextprotocol/serverInfo": serverInfo,
            ])
        }
        return .object(result)
    }

    private func handleNotification(_ request: JSONRPCRequest) {
        if request.method == "notifications/initialized" {
            return
        }
        if request.method == "notifications/cancelled" {
            return
        }
    }

    private var serverInfo: JSONValue {
        .object([
            "name": .string(Self.serverName),
            "version": .string(AwesomeIOSSim.version),
        ])
    }

    private var instructions: String {
        "Inspect inventory and snapshots first. Generate a plan before applying it. "
            + "simulator_apply is a dry run unless confirm is explicitly true."
    }

    private func errorResponse(
        id: JSONValue,
        code: Int,
        message: String,
        data: JSONValue?
    ) -> JSONValue {
        var error: [String: JSONValue] = [
            "code": .integer(code),
            "message": .string(message),
        ]
        if let data { error["data"] = data }
        return .object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "error": .object(error),
        ])
    }

    private func encode(_ value: JSONValue) -> Data? {
        try? StateCodec.encode(value, pretty: false)
    }

    private func encodeValue<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: StateCodec.encode(value, pretty: false))
    }
}

