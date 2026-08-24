import Foundation

public struct SimulatorStateLayerSpec: Codable, Equatable, Sendable {
    public let power: SimulatorPowerState?
    public let eraseBeforeApply: Bool?
    public let applications: [ApplicationSpec]?
    public let preferences: [PreferenceValue]?
    public let statusBar: [String: JSONValue]?

    public init(
        power: SimulatorPowerState? = nil,
        eraseBeforeApply: Bool? = nil,
        applications: [ApplicationSpec]? = nil,
        preferences: [PreferenceValue]? = nil,
        statusBar: [String: JSONValue]? = nil
    ) {
        self.power = power
        self.eraseBeforeApply = eraseBeforeApply
        self.applications = applications
        self.preferences = preferences
        self.statusBar = statusBar
    }

    var isEmpty: Bool {
        power == nil
            && eraseBeforeApply == nil
            && applications == nil
            && preferences == nil
            && statusBar == nil
    }
}

public struct SimulatorStateLayer: Codable, Equatable, Sendable {
    public static let currentAPIVersion = SimulatorStateProfile.currentAPIVersion
    public static let kind = "SimulatorStateLayer"

    public let apiVersion: String
    public let kind: String
    public let metadata: ProfileMetadata
    public let spec: SimulatorStateLayerSpec

    public init(
        apiVersion: String = SimulatorStateLayer.currentAPIVersion,
        kind: String = SimulatorStateLayer.kind,
        metadata: ProfileMetadata,
        spec: SimulatorStateLayerSpec
    ) {
        self.apiVersion = apiVersion
        self.kind = kind
        self.metadata = metadata
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
        guard !spec.isEmpty else {
            throw StateCoreError.invalidProfile("layer spec must contain at least one managed field")
        }

        // Reuse the profile's semantic validator so profiles and layers cannot
        // disagree about application, preference, or status-bar constraints.
        let validationProfile = SimulatorStateProfile(
            metadata: metadata,
            target: .init(udid: "LAYER-VALIDATION"),
            spec: .init(
                power: spec.power ?? .unchanged,
                eraseBeforeApply: spec.eraseBeforeApply ?? false,
                applications: spec.applications ?? [],
                preferences: spec.preferences ?? [],
                statusBar: spec.statusBar
            )
        )
        try validationProfile.validate()
    }
}

public enum SimulatorStateOverlay: Equatable, Sendable {
    case layer(SimulatorStateLayer)
    case preset(String)
}

public struct SimulatorStatePresetDescriptor: Codable, Equatable, Sendable {
    public let name: String
    public let description: String

    public init(name: String, description: String) {
        self.name = name
        self.description = description
    }
}

public enum SimulatorStatePresetCatalog {
    public static let descriptors: [SimulatorStatePresetDescriptor] = [
        .init(name: "booted", description: "Finish with the simulator booted."),
        .init(
            name: "clean-status-bar",
            description: "Use deterministic UI-test status-bar values (09:41, full signal, full battery)."
        ),
        .init(name: "shutdown", description: "Finish with the simulator shut down."),
    ]

    public static let names = descriptors.map(\.name)

    public static func layer(named name: String) throws -> SimulatorStateLayer {
        switch name {
        case "booted":
            return .init(metadata: .init(name: name), spec: .init(power: .booted))
        case "clean-status-bar":
            return .init(
                metadata: .init(name: name),
                spec: .init(statusBar: [
                    "time": .string("09:41"),
                    "dataNetwork": .string("wifi"),
                    "wifiMode": .string("active"),
                    "wifiBars": .integer(3),
                    "cellularMode": .string("active"),
                    "cellularBars": .integer(4),
                    "batteryState": .string("charged"),
                    "batteryLevel": .integer(100),
                ])
            )
        case "shutdown":
            return .init(metadata: .init(name: name), spec: .init(power: .shutdown))
        default:
            throw StateCoreError.unknownPreset(name)
        }
    }
}

public struct SimulatorStateComposer: Sendable {
    public init() {}

    public func compose(
        profile: SimulatorStateProfile,
        overlays: [SimulatorStateOverlay]
    ) throws -> SimulatorStateProfile {
        try profile.validate()
        var spec = profile.spec

        for overlay in overlays {
            let layer: SimulatorStateLayer
            switch overlay {
            case let .layer(value): layer = value
            case let .preset(name): layer = try SimulatorStatePresetCatalog.layer(named: name)
            }
            try layer.validate()
            spec = merge(spec, with: layer.spec)
        }

        let composed = SimulatorStateProfile(
            apiVersion: profile.apiVersion,
            kind: profile.kind,
            metadata: profile.metadata,
            target: profile.target,
            spec: spec
        )
        try composed.validate()
        return composed
    }

    private func merge(
        _ base: DesiredSimulatorState,
        with layer: SimulatorStateLayerSpec
    ) -> DesiredSimulatorState {
        var applications = Dictionary(uniqueKeysWithValues: base.applications.map {
            ($0.bundleIdentifier, $0)
        })
        for application in layer.applications ?? [] {
            applications[application.bundleIdentifier] = application
        }

        var preferences = Dictionary(uniqueKeysWithValues: base.preferences.map {
            ($0.identifier, $0)
        })
        for preference in layer.preferences ?? [] {
            preferences[preference.identifier] = preference
        }

        var statusBar = base.statusBar ?? [:]
        for (key, value) in layer.statusBar ?? [:] {
            statusBar[key] = value
        }

        return DesiredSimulatorState(
            power: layer.power ?? base.power,
            eraseBeforeApply: layer.eraseBeforeApply ?? base.eraseBeforeApply,
            applications: applications.values.sorted { $0.bundleIdentifier < $1.bundleIdentifier },
            preferences: preferences.values.sorted { $0.identifier < $1.identifier },
            statusBar: statusBar.isEmpty ? nil : statusBar
        )
    }
}
