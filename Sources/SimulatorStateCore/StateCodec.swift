import Foundation

public enum StateCodec {
    public static func decodeProfile(from data: Data) throws -> SimulatorStateProfile {
        try ProfileDocumentValidator.validate(data)
        let profile = try decoder().decode(SimulatorStateProfile.self, from: data)
        try profile.validate()
        return profile
    }

    public static func decodeLayer(from data: Data) throws -> SimulatorStateLayer {
        try ProfileDocumentValidator.validateLayer(data)
        let layer = try decoder().decode(SimulatorStateLayer.self, from: data)
        try layer.validate()
        return layer
    }

    public static func decodeSnapshot(from data: Data) throws -> SimulatorSnapshot {
        try decoder().decode(SimulatorSnapshot.self, from: data)
    }

    public static func decodePlan(from data: Data) throws -> SimulatorStatePlan {
        try decoder().decode(SimulatorStatePlan.self, from: data)
    }

    public static func encode<T: Encodable>(_ value: T, pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}
