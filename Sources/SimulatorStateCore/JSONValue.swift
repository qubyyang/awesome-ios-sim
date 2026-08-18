import Foundation

/// A lossless, Sendable representation of the JSON values used by profiles,
/// plans, and MCP structured results.
public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }

    public var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    public var boolValue: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }

    var isScalar: Bool {
        switch self {
        case .bool, .integer, .number, .string: true
        case .null, .array, .object: false
        }
    }

    var isDefaultsCompatible: Bool {
        switch self {
        case .null, .bool, .integer, .number, .string: true
        case let .array(values): values.allSatisfy(\.isScalar)
        case .object: false
        }
    }
}

extension JSONValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .null: "null"
        case let .bool(value): String(value)
        case let .integer(value): String(value)
        case let .number(value): String(value)
        case let .string(value): value
        case let .array(value): "[\(value.map(\.description).joined(separator: ", "))]"
        case let .object(value):
            "{" + value.keys.sorted().map { "\($0): \(value[$0]!.description)" }.joined(separator: ", ") + "}"
        }
    }
}
