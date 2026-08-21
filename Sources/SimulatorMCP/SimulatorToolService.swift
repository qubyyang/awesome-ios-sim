import Foundation
import SimctlDriver
import SimulatorStateCore

struct SimulatorToolService: MCPToolHandling {
    let tools: [MCPToolDefinition] = SimulatorToolService.definitions

    private let controller: any SimulatorControlling
    private let applier: any PlanApplying

    init(controller: any SimulatorControlling) {
        self.controller = controller
        self.applier = SimulatorPlanApplier(controller: controller)
    }

    init(controller: any SimulatorControlling, applier: any PlanApplying) {
        self.controller = controller
        self.applier = applier
    }

    func call(name: String, arguments: [String: JSONValue]) -> MCPToolInvocationResult {
        do {
            switch name {
            case "simulator_inventory":
                let inventory = try controller.inventory()
                return try success(
                    "Found \(inventory.devices.count) simulators across \(inventory.runtimes.count) runtimes.",
                    inventory
                )
            case "simulator_snapshot":
                let udid = try requiredString("udid", arguments)
                let snapshot = try controller.snapshot(udid: udid)
                return try success("Captured state for \(snapshot.device.name) (\(udid)).", snapshot)
            case "simulator_diff", "simulator_plan":
                let profile = try requiredProfile(arguments)
                let snapshot = try resolveSnapshot(arguments, profile: profile)
                let plan = try StatePlanner().makePlan(profile: profile, current: snapshot)
                if name == "simulator_diff" {
                    let value: JSONValue = .object([
                        "profileName": .string(plan.profileName),
                        "targetUDID": .string(plan.targetUDID),
                        "hasChanges": .bool(plan.hasChanges),
                        "diff": try encodeValue(plan.diff),
                        "warnings": .array(plan.warnings.map(JSONValue.string)),
                    ])
                    return .init(
                        text: "Diff contains \(plan.diff.count) entries and \(plan.warnings.count) warnings.",
                        structuredContent: value,
                        isError: false
                    )
                }
                return try success(
                    "Plan contains \(plan.operations.count) operations; maximum risk is \(plan.maximumRisk.rawValue).",
                    plan
                )
            case "simulator_apply":
                let plan: SimulatorStatePlan = try requiredObject("plan", arguments)
                try validate(plan)
                let confirmed = arguments["confirm"]?.boolValue ?? false
                let report = try applier.apply(plan, confirmed: confirmed)
                let text = switch report.status {
                case .dryRun: "Dry run only. Pass confirm: true to execute \(plan.operations.count) operations."
                case .succeeded: "Applied \(report.receipts.count) operations successfully."
                case .failed: "Apply stopped after \(report.receipts.count) operations: \(report.failure ?? "unknown failure")"
                }
                return try .init(
                    text: text,
                    structuredContent: encodeValue(report),
                    isError: report.status == .failed
                )
            default:
                throw MCPProtocolError.invalidParams("Unknown tool: \(name)")
            }
        } catch {
            return .init(
                text: error.localizedDescription,
                structuredContent: .object([
                    "error": .string(error.localizedDescription),
                    "tool": .string(name),
                ]),
                isError: true
            )
        }
    }

    private func resolveSnapshot(
        _ arguments: [String: JSONValue],
        profile: SimulatorStateProfile
    ) throws -> SimulatorSnapshot {
        if arguments["snapshot"] != nil {
            return try requiredObject("snapshot", arguments)
        }
        if let udid = arguments["udid"]?.stringValue ?? profile.target.udid {
            return try controller.snapshot(udid: udid)
        }
        let matches = try controller.inventory().devices.filter(profile.target.matches)
        guard matches.count == 1 else {
            throw StateCoreError.targetMismatch(
                matches.isEmpty
                    ? "no simulator matches the profile selector"
                    : "multiple simulators match; pass udid explicitly"
            )
        }
        return try controller.snapshot(udid: matches[0].udid)
    }

    private func validate(_ plan: SimulatorStatePlan) throws {
        guard !plan.targetUDID.isEmpty else {
            throw StateCoreError.invalidProfile("plan targetUDID is empty")
        }
        guard plan.operations.allSatisfy({ $0.targetUDID == plan.targetUDID }) else {
            throw StateCoreError.invalidProfile("plan operations target different simulators")
        }
        let ids = plan.operations.map(\.id)
        guard Set(ids).count == ids.count else {
            throw StateCoreError.invalidProfile("plan operation IDs must be unique")
        }
    }

    private func success<T: Encodable>(_ text: String, _ value: T) throws -> MCPToolInvocationResult {
        try .init(text: text, structuredContent: encodeValue(value), isError: false)
    }

    private func requiredString(_ key: String, _ arguments: [String: JSONValue]) throws -> String {
        guard let value = arguments[key]?.stringValue, !value.isEmpty else {
            throw MCPProtocolError.invalidParams("\(key) is required")
        }
        return value
    }

    private func requiredObject<T: Decodable>(
        _ key: String,
        _ arguments: [String: JSONValue]
    ) throws -> T {
        guard let value = arguments[key], case .object = value else {
            throw MCPProtocolError.invalidParams("\(key) must be an object")
        }
        return try JSONDecoder().decode(T.self, from: StateCodec.encode(value, pretty: false))
    }

    private func requiredProfile(_ arguments: [String: JSONValue]) throws -> SimulatorStateProfile {
        guard let value = arguments["profile"], case .object = value else {
            throw MCPProtocolError.invalidParams("profile must be an object")
        }
        return try StateCodec.decodeProfile(from: StateCodec.encode(value, pretty: false))
    }

    private func encodeValue<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: StateCodec.encode(value, pretty: false))
    }
}

private extension SimulatorToolService {
    static let objectSchema: JSONValue = .object([
        "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
        "type": .string("object"),
    ])

    static let definitions: [MCPToolDefinition] = [
        .init(
            name: "simulator_inventory",
            title: "List iOS Simulators",
            description: "Read the available iOS Simulator runtimes and devices as deterministic JSON.",
            inputSchema: .object([
                "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
                "type": .string("object"),
                "additionalProperties": .bool(false),
            ]),
            outputSchema: objectSchema,
            annotations: .object([
                "readOnlyHint": .bool(true),
                "destructiveHint": .bool(false),
                "idempotentHint": .bool(true),
                "openWorldHint": .bool(false),
            ])
        ),
        .init(
            name: "simulator_snapshot",
            title: "Capture Simulator State",
            description: "Capture the managed state and capability metadata for one simulator.",
            inputSchema: .object([
                "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
                "type": .string("object"),
                "properties": .object([
                    "udid": .object(["type": .string("string"), "description": .string("Simulator UDID")]),
                ]),
                "required": .array([.string("udid")]),
                "additionalProperties": .bool(false),
            ]),
            outputSchema: objectSchema,
            annotations: .object([
                "readOnlyHint": .bool(true),
                "destructiveHint": .bool(false),
                "idempotentHint": .bool(true),
                "openWorldHint": .bool(false),
            ])
        ),
        .init(
            name: "simulator_diff",
            title: "Diff Simulator State",
            description: "Compare a declarative profile with a supplied snapshot or a live simulator. Never mutates state.",
            inputSchema: planInputSchema,
            outputSchema: objectSchema,
            annotations: .object([
                "readOnlyHint": .bool(true),
                "destructiveHint": .bool(false),
                "idempotentHint": .bool(true),
                "openWorldHint": .bool(false),
            ])
        ),
        .init(
            name: "simulator_plan",
            title: "Plan Simulator State",
            description: "Generate an ordered, reviewable operation plan from a profile. Never mutates state.",
            inputSchema: planInputSchema,
            outputSchema: objectSchema,
            annotations: .object([
                "readOnlyHint": .bool(true),
                "destructiveHint": .bool(false),
                "idempotentHint": .bool(true),
                "openWorldHint": .bool(false),
            ])
        ),
        .init(
            name: "simulator_apply",
            title: "Apply Simulator State Plan",
            description: "Apply a reviewed plan. Defaults to dry-run; mutations occur only when confirm is exactly true.",
            inputSchema: .object([
                "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
                "type": .string("object"),
                "properties": .object([
                    "plan": .object(["type": .string("object"), "description": .string("Plan returned by simulator_plan")]),
                    "confirm": .object([
                        "type": .string("boolean"),
                        "default": .bool(false),
                        "description": .string("Must be true to mutate the simulator"),
                    ]),
                ]),
                "required": .array([.string("plan")]),
                "additionalProperties": .bool(false),
            ]),
            outputSchema: objectSchema,
            annotations: .object([
                "readOnlyHint": .bool(false),
                "destructiveHint": .bool(true),
                "idempotentHint": .bool(false),
                "openWorldHint": .bool(false),
            ])
        ),
    ]

    static let planInputSchema: JSONValue = .object([
        "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
        "type": .string("object"),
        "properties": .object([
            "profile": .object([
                "type": .string("object"),
                "description": .string("awesome-ios-sim/v1alpha1 profile object"),
            ]),
            "snapshot": .object([
                "type": .string("object"),
                "description": .string("Optional snapshot; live state is read when omitted"),
            ]),
            "udid": .object([
                "type": .string("string"),
                "description": .string("Optional explicit live simulator target"),
            ]),
        ]),
        "required": .array([.string("profile")]),
        "additionalProperties": .bool(false),
    ])
}
