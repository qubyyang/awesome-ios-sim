import Foundation

public struct StatePlanner: Sendable {
    public init() {}

    public func makePlan(
        profile: SimulatorStateProfile,
        current: SimulatorSnapshot
    ) throws -> SimulatorStatePlan {
        try profile.validate()
        guard profile.target.matches(current.device) else {
            throw StateCoreError.targetMismatch(
                "profile \(profile.metadata.name) does not match \(current.device.udid)"
            )
        }

        var diff: [StateDiffEntry] = []
        var drafts: [OperationDraft] = []
        var warnings: [String] = []
        let target = current.device.udid

        let hasOnlineChanges = !profile.spec.applications.isEmpty
            || !profile.spec.preferences.isEmpty
            || profile.spec.statusBar != nil
        let initiallyBooted = current.state.power == .booted
        let shouldEndBooted: Bool = switch profile.spec.power {
        case .booted: true
        case .shutdown: false
        case .unchanged: initiallyBooted
        }
        var projectedBooted = initiallyBooted

        if profile.spec.power != .unchanged, shouldEndBooted != initiallyBooted {
            diff.append(.init(
                path: "spec.power",
                kind: .change,
                current: .string(current.state.power.rawValue),
                desired: .string(profile.spec.power.rawValue)
            ))
        }

        if profile.spec.eraseBeforeApply {
            diff.append(.init(
                path: "spec.eraseBeforeApply",
                kind: .change,
                current: .bool(false),
                desired: .bool(true),
                note: "Erasing removes all simulator content and settings."
            ))
            if projectedBooted {
                drafts.append(.init(
                    action: .shutdown,
                    arguments: [:],
                    risk: .reversible,
                    requiresConfirmation: true,
                    reason: "The simulator must be shut down before it can be erased."
                ))
                projectedBooted = false
            }
            drafts.append(.init(
                action: .erase,
                arguments: [:],
                risk: .destructive,
                requiresConfirmation: true,
                reason: "Profile requests a clean simulator before reconciliation."
            ))
        }

        let needsBoot = profile.spec.power == .booted || hasOnlineChanges
        if needsBoot && !projectedBooted {
            drafts.append(.init(
                action: .boot,
                arguments: [:],
                risk: .reversible,
                requiresConfirmation: true,
                reason: "The desired state requires a booted simulator."
            ))
            projectedBooted = true
        }

        planApplications(profile, current, diff: &diff, drafts: &drafts, warnings: &warnings)
        planPreferences(profile, current, diff: &diff, drafts: &drafts, warnings: &warnings)
        planStatusBar(profile, current, diff: &diff, drafts: &drafts, warnings: &warnings)

        if !projectedBooted && shouldEndBooted {
            drafts.append(.init(
                action: .boot,
                arguments: [:],
                risk: .reversible,
                requiresConfirmation: true,
                reason: "Restore the simulator's original booted state."
            ))
        } else if projectedBooted && !shouldEndBooted {
            drafts.append(.init(
                action: .shutdown,
                arguments: [:],
                risk: .reversible,
                requiresConfirmation: true,
                reason: profile.spec.power == .unchanged
                    ? "Restore the simulator's original shutdown state."
                    : "Profile requires the simulator to finish shut down."
            ))
        }

        let operations = drafts.enumerated().map { index, draft in
            SimulatorOperation(
                id: String(format: "%03d-%@", index + 1, draft.action.rawValue),
                action: draft.action,
                targetUDID: target,
                arguments: draft.arguments,
                risk: draft.risk,
                requiresConfirmation: draft.requiresConfirmation,
                reason: draft.reason
            )
        }

        return SimulatorStatePlan(
            profileName: profile.metadata.name,
            targetUDID: target,
            diff: diff.sorted { $0.path < $1.path },
            operations: operations,
            warnings: warnings.sorted()
        )
    }

    private func planApplications(
        _ profile: SimulatorStateProfile,
        _ current: SimulatorSnapshot,
        diff: inout [StateDiffEntry],
        drafts: inout [OperationDraft],
        warnings: inout [String]
    ) {
        guard !profile.spec.applications.isEmpty else { return }
        guard writable("applications", current) else {
            appendUnsupported("applications", current, diff: &diff, warnings: &warnings)
            return
        }

        let installed = Dictionary(uniqueKeysWithValues: current.state.applications.map {
            ($0.bundleIdentifier, $0)
        })

        for app in profile.spec.applications.sorted(by: { $0.bundleIdentifier < $1.bundleIdentifier }) {
            let path = "spec.applications[\(app.bundleIdentifier)]"
            let existing = installed[app.bundleIdentifier]
            switch app.presence {
            case .absent where existing != nil:
                diff.append(.init(path: path, kind: .remove, current: .string("present"), desired: .string("absent")))
                drafts.append(.init(
                    action: .uninstallApplication,
                    arguments: ["bundleIdentifier": .string(app.bundleIdentifier)],
                    risk: .destructive,
                    requiresConfirmation: true,
                    reason: "Application must be absent."
                ))
            case .present where existing == nil:
                diff.append(.init(path: path, kind: .add, current: .string("absent"), desired: .string("present")))
                if let sourcePath = app.sourcePath {
                    drafts.append(.init(
                        action: .installApplication,
                        arguments: [
                            "bundleIdentifier": .string(app.bundleIdentifier),
                            "sourcePath": .string(sourcePath),
                        ],
                        risk: .reversible,
                        requiresConfirmation: true,
                        reason: "Application must be installed."
                    ))
                } else {
                    warnings.append("Cannot install \(app.bundleIdentifier): sourcePath is missing.")
                }
            default:
                break
            }

            guard app.presence == .present, let running = app.running else { continue }
            if running && existing?.running != true && (existing != nil || app.sourcePath != nil) {
                diff.append(.init(
                    path: "\(path).running",
                    kind: .change,
                    current: existing?.running.map(JSONValue.bool),
                    desired: .bool(true)
                ))
                drafts.append(.init(
                    action: .launchApplication,
                    arguments: [
                        "bundleIdentifier": .string(app.bundleIdentifier),
                        "launchArguments": .array(app.launchArguments.map(JSONValue.string)),
                    ],
                    risk: .reversible,
                    requiresConfirmation: true,
                    reason: "Application must be running."
                ))
            } else if !running && existing?.running == true {
                diff.append(.init(
                    path: "\(path).running",
                    kind: .change,
                    current: .bool(true),
                    desired: .bool(false)
                ))
                drafts.append(.init(
                    action: .terminateApplication,
                    arguments: ["bundleIdentifier": .string(app.bundleIdentifier)],
                    risk: .reversible,
                    requiresConfirmation: true,
                    reason: "Application must not be running."
                ))
            }
        }
    }

    private func planPreferences(
        _ profile: SimulatorStateProfile,
        _ current: SimulatorSnapshot,
        diff: inout [StateDiffEntry],
        drafts: inout [OperationDraft],
        warnings: inout [String]
    ) {
        guard !profile.spec.preferences.isEmpty else { return }
        guard writable("preferences", current) else {
            appendUnsupported("preferences", current, diff: &diff, warnings: &warnings)
            return
        }
        let existing = Dictionary(uniqueKeysWithValues: current.state.preferences.map { ($0.identifier, $0) })
        for preference in profile.spec.preferences.sorted(by: { $0.identifier < $1.identifier }) {
            guard existing[preference.identifier]?.value != preference.value else { continue }
            let path = "spec.preferences[\(preference.domain).\(preference.key)]"
            diff.append(.init(
                path: path,
                kind: existing[preference.identifier] == nil ? .add : .change,
                current: existing[preference.identifier]?.value,
                desired: preference.value
            ))
            drafts.append(.init(
                action: .setPreference,
                arguments: [
                    "domain": .string(preference.domain),
                    "key": .string(preference.key),
                    "value": preference.value,
                ],
                risk: .reversible,
                requiresConfirmation: true,
                reason: "Managed preference differs from the profile."
            ))
        }
    }

    private func planStatusBar(
        _ profile: SimulatorStateProfile,
        _ current: SimulatorSnapshot,
        diff: inout [StateDiffEntry],
        drafts: inout [OperationDraft],
        warnings: inout [String]
    ) {
        guard let desired = profile.spec.statusBar else { return }
        guard writable("statusBar", current) else {
            appendUnsupported("statusBar", current, diff: &diff, warnings: &warnings)
            return
        }
        guard current.state.statusBar != desired else { return }
        diff.append(.init(
            path: "spec.statusBar",
            kind: current.state.statusBar == nil ? .add : .change,
            current: current.state.statusBar.map(JSONValue.object),
            desired: .object(desired),
            note: current.capabilities["statusBar"]?.note
        ))
        drafts.append(.init(
            action: .setStatusBar,
            arguments: desired,
            risk: .reversible,
            requiresConfirmation: true,
            reason: "Status bar override differs or cannot be read back exactly."
        ))
    }

    private func writable(_ capability: String, _ snapshot: SimulatorSnapshot) -> Bool {
        snapshot.capabilities[capability]?.writable == true
            && snapshot.capabilities[capability]?.support != .unsupported
    }

    private func appendUnsupported(
        _ capability: String,
        _ snapshot: SimulatorSnapshot,
        diff: inout [StateDiffEntry],
        warnings: inout [String]
    ) {
        let note = snapshot.capabilities[capability]?.note ?? "Capability is not writable."
        diff.append(.init(path: "spec.\(capability)", kind: .unsupported, note: note))
        warnings.append("Skipped \(capability): \(note)")
    }
}

private struct OperationDraft {
    let action: SimulatorOperationAction
    let arguments: [String: JSONValue]
    let risk: OperationRisk
    let requiresConfirmation: Bool
    let reason: String
}
