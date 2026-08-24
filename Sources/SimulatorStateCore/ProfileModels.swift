import Foundation

public struct ProfileMetadata: Codable, Equatable, Sendable {
    public let name: String
    public let description: String?

    public init(name: String, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

public struct SimulatorSelector: Codable, Equatable, Sendable {
    public let udid: String?
    public let name: String?
    public let runtime: String?

    public init(udid: String? = nil, name: String? = nil, runtime: String? = nil) {
        self.udid = udid
        self.name = name
        self.runtime = runtime
    }

    public func matches(_ device: SimulatorDevice) -> Bool {
        if let udid, device.udid != udid { return false }
        if let name, device.name != name { return false }
        if let runtime, device.runtimeIdentifier != runtime { return false }
        return udid != nil || name != nil || runtime != nil
    }
}

public enum ApplicationPresence: String, Codable, Sendable {
    case present
    case absent
}

public struct ApplicationSpec: Codable, Equatable, Sendable {
    public let bundleIdentifier: String
    public let sourcePath: String?
    public let presence: ApplicationPresence
    public let running: Bool?
    public let launchArguments: [String]

    public init(
        bundleIdentifier: String,
        sourcePath: String? = nil,
        presence: ApplicationPresence = .present,
        running: Bool? = nil,
        launchArguments: [String] = []
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.sourcePath = sourcePath
        self.presence = presence
        self.running = running
        self.launchArguments = launchArguments
    }

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case sourcePath
        case presence
        case running
        case launchArguments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        presence = try container.decodeIfPresent(ApplicationPresence.self, forKey: .presence) ?? .present
        running = try container.decodeIfPresent(Bool.self, forKey: .running)
        launchArguments = try container.decodeIfPresent([String].self, forKey: .launchArguments) ?? []
    }
}

public struct DesiredSimulatorState: Codable, Equatable, Sendable {
    public let power: SimulatorPowerState
    public let eraseBeforeApply: Bool
    public let applications: [ApplicationSpec]
    public let preferences: [PreferenceValue]
    public let statusBar: [String: JSONValue]?

    public init(
        power: SimulatorPowerState = .unchanged,
        eraseBeforeApply: Bool = false,
        applications: [ApplicationSpec] = [],
        preferences: [PreferenceValue] = [],
        statusBar: [String: JSONValue]? = nil
    ) {
        self.power = power
        self.eraseBeforeApply = eraseBeforeApply
        self.applications = applications
        self.preferences = preferences
        self.statusBar = statusBar
    }

    private enum CodingKeys: String, CodingKey {
        case power
        case eraseBeforeApply
        case applications
        case preferences
        case statusBar
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        power = try container.decodeIfPresent(SimulatorPowerState.self, forKey: .power) ?? .unchanged
        eraseBeforeApply = try container.decodeIfPresent(Bool.self, forKey: .eraseBeforeApply) ?? false
        applications = try container.decodeIfPresent([ApplicationSpec].self, forKey: .applications) ?? []
        preferences = try container.decodeIfPresent([PreferenceValue].self, forKey: .preferences) ?? []
        statusBar = try container.decodeIfPresent([String: JSONValue].self, forKey: .statusBar)
    }
}

public struct SimulatorStateProfile: Codable, Equatable, Sendable {
    public static let currentAPIVersion = "awesome-ios-sim/v1alpha1"
    public static let kind = "SimulatorState"

    public let apiVersion: String
    public let kind: String
    public let metadata: ProfileMetadata
    public let target: SimulatorSelector
    public let spec: DesiredSimulatorState

    public init(
        apiVersion: String = SimulatorStateProfile.currentAPIVersion,
        kind: String = SimulatorStateProfile.kind,
        metadata: ProfileMetadata,
        target: SimulatorSelector,
        spec: DesiredSimulatorState
    ) {
        self.apiVersion = apiVersion
        self.kind = kind
        self.metadata = metadata
        self.target = target
        self.spec = spec
    }

    public func validate() throws {
        guard apiVersion == Self.currentAPIVersion else {
            throw StateCoreError.unsupportedAPIVersion(apiVersion)
        }
        guard kind == Self.kind else {
            throw StateCoreError.invalidProfile("kind must be \(Self.kind)")
        }
        guard !metadata.name.isEmpty else {
            throw StateCoreError.invalidProfile("metadata.name must not be empty")
        }
        guard target.udid != nil || target.name != nil || target.runtime != nil else {
            throw StateCoreError.invalidProfile("target must include udid, name, or runtime")
        }
        guard [target.udid, target.name, target.runtime].compactMap({ $0 }).allSatisfy({ !$0.isEmpty }) else {
            throw StateCoreError.invalidProfile("target values must not be empty")
        }

        let appIDs = spec.applications.map(\.bundleIdentifier)
        guard appIDs.allSatisfy({ !$0.isEmpty }) else {
            throw StateCoreError.invalidProfile("application bundle identifiers must not be empty")
        }
        guard Set(appIDs).count == appIDs.count else {
            throw StateCoreError.invalidProfile("application bundle identifiers must be unique")
        }
        guard spec.applications.compactMap(\.sourcePath).allSatisfy({ !$0.isEmpty }) else {
            throw StateCoreError.invalidProfile("application source paths must not be empty")
        }
        guard !spec.applications.contains(where: { $0.presence == .absent && $0.sourcePath != nil }) else {
            throw StateCoreError.invalidProfile("absent applications must not include sourcePath")
        }

        let preferenceIDs = spec.preferences.map(\.identifier)
        guard spec.preferences.allSatisfy({ !$0.domain.isEmpty && !$0.key.isEmpty }) else {
            throw StateCoreError.invalidProfile("preference domains and keys must not be empty")
        }
        guard Set(preferenceIDs).count == preferenceIDs.count else {
            throw StateCoreError.invalidProfile("preference domain/key pairs must be unique")
        }
        guard spec.preferences.allSatisfy({ $0.value.isDefaultsCompatible }) else {
            throw StateCoreError.invalidProfile(
                "preference values must be null, a scalar, or an array of scalars"
            )
        }

        if let statusBar = spec.statusBar {
            try validateStatusBar(statusBar)
        }
    }

    private func validateStatusBar(_ statusBar: [String: JSONValue]) throws {
        guard !statusBar.isEmpty else {
            throw StateCoreError.invalidProfile("statusBar must contain at least one override")
        }

        let allowedKeys: Set<String> = [
            "time", "dataNetwork", "wifiMode", "wifiBars", "cellularMode",
            "cellularBars", "operatorName", "batteryState", "batteryLevel",
        ]
        let unknownKeys = Set(statusBar.keys).subtracting(allowedKeys).sorted()
        guard unknownKeys.isEmpty else {
            throw StateCoreError.invalidProfile(
                "unsupported statusBar keys: \(unknownKeys.joined(separator: ", "))"
            )
        }

        try requireString("time", in: statusBar)
        try requireString("operatorName", in: statusBar)
        try requireEnum(
            "dataNetwork",
            values: ["hide", "wifi", "3g", "4g", "lte", "lte-a", "lte+", "5g", "5g+", "5g-uwb", "5g-uc"],
            in: statusBar
        )
        try requireEnum("wifiMode", values: ["searching", "failed", "active"], in: statusBar)
        try requireEnum(
            "cellularMode",
            values: ["notSupported", "searching", "failed", "active"],
            in: statusBar
        )
        try requireEnum("batteryState", values: ["charging", "charged", "discharging"], in: statusBar)
        try requireInteger("wifiBars", range: 0 ... 3, in: statusBar)
        try requireInteger("cellularBars", range: 0 ... 4, in: statusBar)
        try requireInteger("batteryLevel", range: 0 ... 100, in: statusBar)
    }

    private func requireString(_ key: String, in values: [String: JSONValue]) throws {
        guard let value = values[key] else { return }
        guard case .string = value else {
            throw StateCoreError.invalidProfile("statusBar.\(key) must be a string")
        }
    }

    private func requireEnum(
        _ key: String,
        values allowed: Set<String>,
        in values: [String: JSONValue]
    ) throws {
        guard let value = values[key] else { return }
        guard case let .string(candidate) = value, allowed.contains(candidate) else {
            throw StateCoreError.invalidProfile("statusBar.\(key) has an unsupported value")
        }
    }

    private func requireInteger(
        _ key: String,
        range: ClosedRange<Int>,
        in values: [String: JSONValue]
    ) throws {
        guard let value = values[key] else { return }
        guard case let .integer(candidate) = value, range.contains(candidate) else {
            throw StateCoreError.invalidProfile(
                "statusBar.\(key) must be an integer from \(range.lowerBound) through \(range.upperBound)"
            )
        }
    }
}

public enum StateCoreError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedAPIVersion(String)
    case invalidProfile(String)
    case targetMismatch(String)
    case unknownPreset(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedAPIVersion(version): "Unsupported API version: \(version)"
        case let .invalidProfile(message): "Invalid profile: \(message)"
        case let .targetMismatch(message): "Target mismatch: \(message)"
        case let .unknownPreset(name):
            "Unknown preset: \(name). Available presets: \(SimulatorStatePresetCatalog.names.joined(separator: ", "))"
        }
    }
}
