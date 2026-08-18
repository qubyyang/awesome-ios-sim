import Foundation

public enum SimulatorPowerState: String, Codable, CaseIterable, Sendable {
    case booted
    case shutdown
    case unchanged
}

public enum SimulatorDeviceState: String, Codable, Sendable {
    case booted = "Booted"
    case shutdown = "Shutdown"
    case creating = "Creating"
    case unknown = "Unknown"
}

public struct SimulatorRuntime: Codable, Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let version: String?
    public let isAvailable: Bool

    public init(identifier: String, name: String, version: String? = nil, isAvailable: Bool = true) {
        self.identifier = identifier
        self.name = name
        self.version = version
        self.isAvailable = isAvailable
    }
}

public struct SimulatorDevice: Codable, Equatable, Sendable {
    public let udid: String
    public let name: String
    public let state: SimulatorDeviceState
    public let runtimeIdentifier: String
    public let isAvailable: Bool
    public let dataPath: String?

    public init(
        udid: String,
        name: String,
        state: SimulatorDeviceState,
        runtimeIdentifier: String,
        isAvailable: Bool = true,
        dataPath: String? = nil
    ) {
        self.udid = udid
        self.name = name
        self.state = state
        self.runtimeIdentifier = runtimeIdentifier
        self.isAvailable = isAvailable
        self.dataPath = dataPath
    }
}

public struct SimulatorInventory: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let developerDirectory: String?
    public let runtimes: [SimulatorRuntime]
    public let devices: [SimulatorDevice]

    public init(
        generatedAt: String = StateTimestamp.now(),
        developerDirectory: String? = nil,
        runtimes: [SimulatorRuntime],
        devices: [SimulatorDevice]
    ) {
        self.generatedAt = generatedAt
        self.developerDirectory = developerDirectory
        self.runtimes = runtimes
        self.devices = devices
    }
}

public enum CapabilitySupport: String, Codable, Sendable {
    case exact
    case bestEffort
    case unsupported
}

public struct StateCapability: Codable, Equatable, Sendable {
    public let support: CapabilitySupport
    public let readable: Bool
    public let writable: Bool
    public let note: String?

    public init(
        support: CapabilitySupport,
        readable: Bool,
        writable: Bool,
        note: String? = nil
    ) {
        self.support = support
        self.readable = readable
        self.writable = writable
        self.note = note
    }
}

public struct InstalledApplication: Codable, Equatable, Sendable {
    public let bundleIdentifier: String
    public let bundlePath: String?
    public let running: Bool?

    public init(bundleIdentifier: String, bundlePath: String? = nil, running: Bool? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.bundlePath = bundlePath
        self.running = running
    }
}

public struct PreferenceValue: Codable, Equatable, Sendable {
    public let domain: String
    public let key: String
    public let value: JSONValue

    public init(domain: String, key: String, value: JSONValue) {
        self.domain = domain
        self.key = key
        self.value = value
    }

    public var identifier: String { "\(domain)::\(key)" }
}

public struct SimulatorManagedState: Codable, Equatable, Sendable {
    public let power: SimulatorPowerState
    public let applications: [InstalledApplication]
    public let preferences: [PreferenceValue]
    public let statusBar: [String: JSONValue]?

    public init(
        power: SimulatorPowerState,
        applications: [InstalledApplication] = [],
        preferences: [PreferenceValue] = [],
        statusBar: [String: JSONValue]? = nil
    ) {
        self.power = power
        self.applications = applications
        self.preferences = preferences
        self.statusBar = statusBar
    }
}

public struct SimulatorSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion = "awesome-ios-sim/snapshot-v1alpha1"

    public let apiVersion: String
    public let generatedAt: String
    public let device: SimulatorDevice
    public let state: SimulatorManagedState
    public let capabilities: [String: StateCapability]

    public init(
        apiVersion: String = SimulatorSnapshot.schemaVersion,
        generatedAt: String = StateTimestamp.now(),
        device: SimulatorDevice,
        state: SimulatorManagedState,
        capabilities: [String: StateCapability] = SimulatorSnapshot.defaultCapabilities
    ) {
        self.apiVersion = apiVersion
        self.generatedAt = generatedAt
        self.device = device
        self.state = state
        self.capabilities = capabilities
    }

    public static let defaultCapabilities: [String: StateCapability] = [
        "power": StateCapability(support: .exact, readable: true, writable: true),
        "applications": StateCapability(support: .bestEffort, readable: true, writable: true),
        "preferences": StateCapability(
            support: .bestEffort,
            readable: false,
            writable: true,
            note: "Only explicitly managed preference keys can be compared reliably."
        ),
        "statusBar": StateCapability(
            support: .bestEffort,
            readable: false,
            writable: true,
            note: "simctl supports overrides but does not expose a complete readback API."
        ),
    ]
}

public struct StateTimestamp: Sendable {
    public static func now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

