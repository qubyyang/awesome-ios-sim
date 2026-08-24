import Darwin
import Foundation
import SimctlDriver
import SimulatorStateCore

private enum CLIError: Error, LocalizedError {
    case usage(String)
    case file(String)
    case ambiguousTarget([String])
    case invalidPlan(String)

    var errorDescription: String? {
        switch self {
        case let .usage(message): message
        case let .file(message): message
        case let .ambiguousTarget(devices):
            "Profile matches multiple simulators; pass --device with one of: \(devices.joined(separator: ", "))"
        case let .invalidPlan(message): "Invalid plan: \(message)"
        }
    }
}

private struct DiffDocument: Encodable {
    let profileName: String
    let targetUDID: String
    let hasChanges: Bool
    let diff: [StateDiffEntry]
    let warnings: [String]
}

private struct Arguments {
    let values: [String]

    var command: String? { values.first }

    func contains(_ flag: String) -> Bool {
        values.contains(flag)
    }

    func value(after option: String) throws -> String? {
        guard let index = values.firstIndex(of: option) else { return nil }
        let valueIndex = values.index(after: index)
        guard valueIndex < values.endIndex, !values[valueIndex].hasPrefix("--") else {
            throw CLIError.usage("\(option) requires a value")
        }
        return values[valueIndex]
    }

    func requiredValue(after option: String) throws -> String {
        guard let value = try value(after: option) else {
            throw CLIError.usage("Missing required option \(option)")
        }
        return value
    }

    func overlays() throws -> [SimulatorStateOverlay] {
        var result: [SimulatorStateOverlay] = []
        var index = values.startIndex
        while index < values.endIndex {
            let option = values[index]
            guard option == "--layer" || option == "--preset" else {
                index = values.index(after: index)
                continue
            }
            let valueIndex = values.index(after: index)
            guard valueIndex < values.endIndex, !values[valueIndex].hasPrefix("--") else {
                throw CLIError.usage("\(option) requires a value")
            }
            if option == "--preset" {
                result.append(.preset(values[valueIndex]))
            } else {
                let layer = try StateCodec.decodeLayer(from: readData(path: values[valueIndex]))
                result.append(.layer(layer))
            }
            index = values.index(after: valueIndex)
        }
        return result
    }
}

private let help = """
awesome-ios-sim — Simulator State as Code

USAGE
  ios-sim-state inventory
  ios-sim-state snapshot --device <UDID>
  ios-sim-state presets
  ios-sim-state compose --profile <profile.json> [--layer <layer.json> | --preset <name>]...
  ios-sim-state diff --profile <profile.json> [overlays] [--snapshot <snapshot.json> | --device <UDID>]
  ios-sim-state plan --profile <profile.json> [overlays] [--snapshot <snapshot.json> | --device <UDID>]
  ios-sim-state apply --plan <plan.json> [--confirm] [--journal <report.json>]

OVERLAYS
  --layer <file>   Merge a reusable SimulatorStateLayer document.
  --preset <name>  Merge a built-in preset. Repeat either option; order is preserved.

SAFETY
  `plan` and `diff` never mutate a simulator.
  `apply` is a dry run unless --confirm is explicitly present.
  Execution stops on the first failed operation and emits an auditable report.

OPTIONS
  --compact     Emit compact JSON instead of pretty JSON.
  --version     Print the current version.
  --help        Show this help.
"""

private func readData(path: String) throws -> Data {
    let url = URL(fileURLWithPath: path)
    do {
        return try Data(contentsOf: url)
    } catch {
        throw CLIError.file("Could not read \(url.path): \(error.localizedDescription)")
    }
}

private func emit<T: Encodable>(_ value: T, pretty: Bool) throws {
    let data = try StateCodec.encode(value, pretty: pretty)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

private func writeJournal(_ report: PlanExecutionReport, path: String) throws {
    let url = URL(fileURLWithPath: path)
    do {
        try StateCodec.encode(report).write(to: url, options: .atomic)
    } catch {
        throw CLIError.file("Could not write journal \(url.path): \(error.localizedDescription)")
    }
}

private func validate(_ plan: SimulatorStatePlan) throws {
    guard !plan.targetUDID.isEmpty else {
        throw CLIError.invalidPlan("targetUDID is empty")
    }
    guard plan.operations.allSatisfy({ $0.targetUDID == plan.targetUDID }) else {
        throw CLIError.invalidPlan("every operation must target plan.targetUDID")
    }
    let ids = plan.operations.map(\.id)
    guard Set(ids).count == ids.count else {
        throw CLIError.invalidPlan("operation IDs must be unique")
    }
}

private func resolveSnapshot(
    arguments: Arguments,
    profile: SimulatorStateProfile,
    client: SimctlClient
) throws -> SimulatorSnapshot {
    if let path = try arguments.value(after: "--snapshot") {
        return try StateCodec.decodeSnapshot(from: readData(path: path))
    }

    if let explicitUDID = try arguments.value(after: "--device") {
        return try client.snapshot(udid: explicitUDID)
    }
    if let profileUDID = profile.target.udid {
        return try client.snapshot(udid: profileUDID)
    }

    let matches = try client.inventory().devices.filter(profile.target.matches)
    guard !matches.isEmpty else {
        throw SimctlDriverError.deviceNotFound("no device matches profile selector")
    }
    guard matches.count == 1 else {
        throw CLIError.ambiguousTarget(matches.map { "\($0.name) (\($0.udid))" })
    }
    return try client.snapshot(udid: matches[0].udid)
}

private func run() throws {
    let arguments = Arguments(values: Array(CommandLine.arguments.dropFirst()))
    if arguments.values.isEmpty || arguments.contains("--help") || arguments.command == "help" {
        print(help)
        return
    }
    if arguments.contains("--version") || arguments.command == "version" {
        print(AwesomeIOSSim.version)
        return
    }

    let pretty = !arguments.contains("--compact")
    let client = SimctlClient()
    switch arguments.command {
    case "inventory":
        try emit(client.inventory(), pretty: pretty)

    case "snapshot":
        let udid = try arguments.requiredValue(after: "--device")
        try emit(client.snapshot(udid: udid), pretty: pretty)

    case "presets":
        try emit(SimulatorStatePresetCatalog.descriptors, pretty: pretty)

    case "compose", "diff", "plan":
        let profilePath = try arguments.requiredValue(after: "--profile")
        let baseProfile = try StateCodec.decodeProfile(from: readData(path: profilePath))
        let profile = try SimulatorStateComposer().compose(
            profile: baseProfile,
            overlays: arguments.overlays()
        )
        if arguments.command == "compose" {
            try emit(profile, pretty: pretty)
            return
        }
        let snapshot = try resolveSnapshot(arguments: arguments, profile: profile, client: client)
        let plan = try StatePlanner().makePlan(profile: profile, current: snapshot)
        if arguments.command == "diff" {
            try emit(
                DiffDocument(
                    profileName: plan.profileName,
                    targetUDID: plan.targetUDID,
                    hasChanges: plan.hasChanges,
                    diff: plan.diff,
                    warnings: plan.warnings
                ),
                pretty: pretty
            )
        } else {
            try emit(plan, pretty: pretty)
        }

    case "apply":
        let planPath = try arguments.requiredValue(after: "--plan")
        let plan = try StateCodec.decodePlan(from: readData(path: planPath))
        try validate(plan)
        let report = try SimulatorPlanApplier(controller: client).apply(
            plan,
            confirmed: arguments.contains("--confirm")
        )
        if let journalPath = try arguments.value(after: "--journal") {
            try writeJournal(report, path: journalPath)
        }
        try emit(report, pretty: pretty)
        if report.status == .failed { exit(2) }

    default:
        throw CLIError.usage("Unknown command: \(arguments.command ?? "")\n\n\(help)")
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
