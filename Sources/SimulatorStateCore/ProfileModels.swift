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
        guard target.udid != nil || target.name != nil || target.runtime != nil else {
            throw StateCoreError.invalidProfile("target must include udid, name, or runtime")
        }

        let appIDs = spec.applications.map(\.bundleIdentifier)
        guard Set(appIDs).count == appIDs.count else {
            throw StateCoreError.invalidProfile("application bundle identifiers must be unique")
        }
        guard !spec.applications.contains(where: { $0.presence == .absent && $0.sourcePath != nil }) else {
            throw StateCoreError.invalidProfile("absent applications must not include sourcePath")
        }

        let preferenceIDs = spec.preferences.map(\.identifier)
        guard Set(preferenceIDs).count == preferenceIDs.count else {
            throw StateCoreError.invalidProfile("preference domain/key pairs must be unique")
        }
        guard spec.preferences.allSatisfy({ $0.value.isDefaultsCompatible }) else {
            throw StateCoreError.invalidProfile(
                "preference values must be null, a scalar, or an array of scalars"
            )
        }

        if let statusBar = spec.statusBar {
            guard statusBar.keys.allSatisfy({
                $0.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil
            }) else {
                throw StateCoreError.invalidProfile("status bar keys must contain only letters, digits, or hyphens")
            }
            guard statusBar.values.allSatisfy(\.isScalar) else {
                throw StateCoreError.invalidProfile("status bar values must be scalars")
            }
        }
    }
}

public enum StateCoreError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedAPIVersion(String)
    case invalidProfile(String)
    case targetMismatch(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedAPIVersion(version): "Unsupported API version: \(version)"
        case let .invalidProfile(message): "Invalid profile: \(message)"
        case let .targetMismatch(message): "Target mismatch: \(message)"
        }
    }
}
