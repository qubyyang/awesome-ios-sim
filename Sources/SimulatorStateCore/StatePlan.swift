import Foundation

public enum StateDiffKind: String, Codable, Sendable {
    case add
    case change
    case remove
    case unsupported
}

public struct StateDiffEntry: Codable, Equatable, Sendable {
    public let path: String
    public let kind: StateDiffKind
    public let current: JSONValue?
    public let desired: JSONValue?
    public let note: String?

    public init(
        path: String,
        kind: StateDiffKind,
        current: JSONValue? = nil,
        desired: JSONValue? = nil,
        note: String? = nil
    ) {
        self.path = path
        self.kind = kind
        self.current = current
        self.desired = desired
        self.note = note
    }
}

public enum SimulatorOperationAction: String, Codable, Sendable {
    case erase
    case boot
    case shutdown
    case installApplication
    case uninstallApplication
    case launchApplication
    case terminateApplication
    case setPreference
    case setStatusBar
}

public enum OperationRisk: String, Codable, Comparable, Sendable {
    case readOnly
    case reversible
    case destructive

    private var rank: Int {
        switch self {
        case .readOnly: 0
        case .reversible: 1
        case .destructive: 2
        }
    }

    public static func < (lhs: OperationRisk, rhs: OperationRisk) -> Bool {
        lhs.rank < rhs.rank
    }
}

public struct SimulatorOperation: Codable, Equatable, Sendable {
    public let id: String
    public let action: SimulatorOperationAction
    public let targetUDID: String
    public let arguments: [String: JSONValue]
    public let risk: OperationRisk
    public let requiresConfirmation: Bool
    public let reason: String

    public init(
        id: String,
        action: SimulatorOperationAction,
        targetUDID: String,
        arguments: [String: JSONValue] = [:],
        risk: OperationRisk,
        requiresConfirmation: Bool,
        reason: String
    ) {
        self.id = id
        self.action = action
        self.targetUDID = targetUDID
        self.arguments = arguments
        self.risk = risk
        self.requiresConfirmation = requiresConfirmation
        self.reason = reason
    }
}

public struct SimulatorStatePlan: Codable, Equatable, Sendable {
    public let profileName: String
    public let targetUDID: String
    public let generatedAt: String
    public let diff: [StateDiffEntry]
    public let operations: [SimulatorOperation]
    public let warnings: [String]

    public init(
        profileName: String,
        targetUDID: String,
        generatedAt: String = StateTimestamp.now(),
        diff: [StateDiffEntry],
        operations: [SimulatorOperation],
        warnings: [String] = []
    ) {
        self.profileName = profileName
        self.targetUDID = targetUDID
        self.generatedAt = generatedAt
        self.diff = diff
        self.operations = operations
        self.warnings = warnings
    }

    public var hasChanges: Bool { !diff.isEmpty }
    public var requiresConfirmation: Bool { operations.contains { $0.requiresConfirmation } }
    public var maximumRisk: OperationRisk { operations.map(\.risk).max() ?? .readOnly }
}
