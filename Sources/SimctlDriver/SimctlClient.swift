import Foundation
import SimulatorStateCore

public enum SimctlDriverError: Error, Equatable, LocalizedError, Sendable {
    case processLaunch(String, String)
    case commandFailed(arguments: [String], exitCode: Int32, message: String)
    case malformedOutput(String)
    case deviceNotFound(String)
    case unsupportedPreferenceValue(String)
    case invalidStatusBarKey(String)
    case confirmationRequired
    case io(String)

    public var errorDescription: String? {
        switch self {
        case let .processLaunch(executable, message): "Could not launch \(executable): \(message)"
        case let .commandFailed(arguments, exitCode, message):
            "simctl \(arguments.joined(separator: " ")) failed (\(exitCode)): \(message)"
        case let .malformedOutput(message): "Malformed simctl output: \(message)"
        case let .deviceNotFound(udid): "Simulator not found: \(udid)"
        case let .unsupportedPreferenceValue(message): "Unsupported preference value: \(message)"
        case let .invalidStatusBarKey(key): "Invalid status bar key: \(key)"
        case .confirmationRequired: "Applying a state plan requires explicit confirmation"
        case let .io(message): "I/O error: \(message)"
        }
    }
}

public protocol SimulatorControlling: Sendable {
    func inventory() throws -> SimulatorInventory
    func snapshot(udid: String) throws -> SimulatorSnapshot
    func execute(_ operation: SimulatorOperation) throws -> OperationReceipt
}

public struct SimctlClient: SimulatorControlling {
    public static let xcrunPath = "/usr/bin/xcrun"

    private let executor: any CommandExecuting
    private let environment: [String: String]

    public init(
        executor: any CommandExecuting = FoundationCommandExecutor(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executor = executor
        self.environment = environment
    }

    public func inventory() throws -> SimulatorInventory {
        let result = try run(["list", "--json"])
        guard result.succeeded else { throw commandError(result) }
        return try SimctlOutputParser.inventory(
            data: Data(result.standardOutput.utf8),
            developerDirectory: environment["DEVELOPER_DIR"]
        )
    }

    public func snapshot(udid: String) throws -> SimulatorSnapshot {
        let inventory = try inventory()
        guard let device = inventory.devices.first(where: { $0.udid == udid }) else {
            throw SimctlDriverError.deviceNotFound(udid)
        }

        var capabilities = SimulatorSnapshot.defaultCapabilities
        var applications: [InstalledApplication] = []
        let jsonResult = try run(["listapps", "--json", udid])
        if jsonResult.succeeded,
           let parsed = try? SimctlOutputParser.applications(data: Data(jsonResult.standardOutput.utf8))
        {
            applications = parsed
        } else {
            let plistResult = try run(["listapps", udid])
            if plistResult.succeeded,
               let parsed = try? SimctlOutputParser.applications(data: Data(plistResult.standardOutput.utf8))
            {
                applications = parsed
            } else {
                capabilities["applications"] = StateCapability(
                    support: .bestEffort,
                    readable: false,
                    writable: true,
                    note: "Installed apps could not be read; mutations remain available."
                )
            }
        }

        return SimulatorSnapshot(
            device: device,
            state: SimulatorManagedState(
                power: device.state == .booted ? .booted : .shutdown,
                applications: applications.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
            ),
            capabilities: capabilities
        )
    }

    public func execute(_ operation: SimulatorOperation) throws -> OperationReceipt {
        let arguments = try commandArguments(for: operation)
        let startedAt = StateTimestamp.now()
        let result = try run(arguments)
        return OperationReceipt(
            operationID: operation.id,
            action: operation.action,
            targetUDID: operation.targetUDID,
            command: ["xcrun", "simctl"] + arguments,
            exitCode: result.exitCode,
            standardOutput: result.standardOutput,
            standardError: result.standardError,
            startedAt: startedAt,
            finishedAt: StateTimestamp.now()
        )
    }

    private func commandArguments(for operation: SimulatorOperation) throws -> [String] {
        let udid = operation.targetUDID
        switch operation.action {
        case .erase:
            return ["erase", udid]
        case .boot:
            return ["boot", udid]
        case .shutdown:
            return ["shutdown", udid]
        case .installApplication:
            return ["install", udid, try requiredString("sourcePath", operation)]
        case .uninstallApplication:
            return ["uninstall", udid, try requiredString("bundleIdentifier", operation)]
        case .launchApplication:
            var result = ["launch", udid, try requiredString("bundleIdentifier", operation)]
            if case let .array(values)? = operation.arguments["launchArguments"] {
                result.append(contentsOf: values.compactMap(\.stringValue))
            }
            return result
        case .terminateApplication:
            return ["terminate", udid, try requiredString("bundleIdentifier", operation)]
        case .setPreference:
            let domain = try requiredString("domain", operation)
            let key = try requiredString("key", operation)
            guard let value = operation.arguments["value"] else {
                throw SimctlDriverError.unsupportedPreferenceValue("missing value")
            }
            return ["spawn", udid, "defaults"] + (try preferenceArguments(domain: domain, key: key, value: value))
        case .setStatusBar:
            var result = ["status_bar", udid, "override"]
            for key in operation.arguments.keys.sorted() {
                guard key.range(of: "^[A-Za-z0-9-]+$", options: .regularExpression) != nil else {
                    throw SimctlDriverError.invalidStatusBarKey(key)
                }
                result.append("--\(key)")
                result.append(try scalarString(operation.arguments[key]!))
            }
            return result
        }
    }

    private func preferenceArguments(domain: String, key: String, value: JSONValue) throws -> [String] {
        switch value {
        case .null:
            return ["delete", domain, key]
        case let .bool(value):
            return ["write", domain, key, "-bool", String(value)]
        case let .integer(value):
            return ["write", domain, key, "-int", String(value)]
        case let .number(value):
            return ["write", domain, key, "-float", String(value)]
        case let .string(value):
            return ["write", domain, key, "-string", value]
        case let .array(values):
            return ["write", domain, key, "-array"] + (try values.map(scalarString))
        case .object:
            throw SimctlDriverError.unsupportedPreferenceValue("objects are not supported by the defaults adapter")
        }
    }

    private func scalarString(_ value: JSONValue) throws -> String {
        switch value {
        case let .bool(value): String(value)
        case let .integer(value): String(value)
        case let .number(value): String(value)
        case let .string(value): value
        case .null, .array, .object:
            throw SimctlDriverError.unsupportedPreferenceValue("expected a scalar value")
        }
    }

    private func requiredString(_ key: String, _ operation: SimulatorOperation) throws -> String {
        guard let value = operation.arguments[key]?.stringValue, !value.isEmpty else {
            throw SimctlDriverError.malformedOutput("operation \(operation.id) is missing \(key)")
        }
        return value
    }

    private func run(_ simctlArguments: [String]) throws -> CommandResult {
        try executor.run(executable: Self.xcrunPath, arguments: ["simctl"] + simctlArguments)
    }

    private func commandError(_ result: CommandResult) -> SimctlDriverError {
        SimctlDriverError.commandFailed(
            arguments: Array(result.arguments.dropFirst()),
            exitCode: result.exitCode,
            message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

