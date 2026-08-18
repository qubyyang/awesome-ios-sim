import Foundation
import SimulatorStateCore

struct JSONRPCRequest: Decodable {
    let jsonrpc: String
    let id: JSONValue?
    let method: String
    let params: [String: JSONValue]?
}

struct MCPToolDefinition: Encodable, Equatable, Sendable {
    let name: String
    let title: String
    let description: String
    let inputSchema: JSONValue
    let outputSchema: JSONValue
    let annotations: JSONValue
}

struct MCPToolInvocationResult: Equatable, Sendable {
    let text: String
    let structuredContent: JSONValue
    let isError: Bool
}

protocol MCPToolHandling: Sendable {
    var tools: [MCPToolDefinition] { get }
    func call(name: String, arguments: [String: JSONValue]) -> MCPToolInvocationResult
}

struct MCPProtocolError: Error, LocalizedError, Sendable {
    let code: Int
    let message: String
    let data: JSONValue?

    static func invalidParams(_ message: String) -> MCPProtocolError {
        .init(code: -32602, message: message, data: nil)
    }

    static func methodNotFound(_ method: String) -> MCPProtocolError {
        .init(code: -32601, message: "Method not found: \(method)", data: nil)
    }

    var errorDescription: String? { message }
}

enum MCPProtocolEra: Equatable {
    case current
    case legacy(String)
}
