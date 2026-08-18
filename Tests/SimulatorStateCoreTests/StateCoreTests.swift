import Foundation
import Testing
@testable import SimulatorStateCore

private let device = SimulatorDevice(
    udid: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
    name: "iPhone 17 Pro",
    state: .shutdown,
    runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
)

@Test func profileRoundTripsAsStableJSON() throws {
    let profile = SimulatorStateProfile(
        metadata: .init(name: "ui-tests"),
        target: .init(udid: device.udid),
        spec: .init(
            power: .booted,
            preferences: [.init(domain: "com.example.app", key: "onboarding", value: .bool(false))]
        )
    )

    let encoded = try StateCodec.encode(profile)
    let decoded = try StateCodec.decodeProfile(from: encoded)
    #expect(decoded == profile)
    #expect(String(decoding: encoded, as: UTF8.self).contains("awesome-ios-sim/v1alpha1"))
}

@Test func invalidProfilesAreRejected() {
    let profile = SimulatorStateProfile(
        metadata: .init(name: "invalid"),
        target: .init(),
        spec: .init()
    )
    #expect(throws: StateCoreError.self) {
        try profile.validate()
    }
}

@Test func plannerProducesDeterministicSafeOrder() throws {
    let current = SimulatorSnapshot(
        generatedAt: "2026-08-18T00:00:00Z",
        device: device,
        state: .init(power: .shutdown)
    )
    let profile = SimulatorStateProfile(
        metadata: .init(name: "agent-fixture"),
        target: .init(name: device.name, runtime: device.runtimeIdentifier),
        spec: .init(
            power: .shutdown,
            applications: [
                .init(
                    bundleIdentifier: "com.example.app",
                    sourcePath: "/tmp/Example.app",
                    running: true,
                    launchArguments: ["--uitesting"]
                ),
            ],
            preferences: [
                .init(domain: "com.example.app", key: "hasSeenOnboarding", value: .bool(false)),
            ],
            statusBar: ["time": .string("09:41")]
        )
    )

    let plan = try StatePlanner().makePlan(profile: profile, current: current)
    #expect(plan.operations.map(\.action) == [
        .boot,
        .installApplication,
        .launchApplication,
        .setPreference,
        .setStatusBar,
        .shutdown,
    ])
    #expect(plan.operations.map(\.id) == [
        "001-boot",
        "002-installApplication",
        "003-launchApplication",
        "004-setPreference",
        "005-setStatusBar",
        "006-shutdown",
    ])
    #expect(plan.requiresConfirmation)
    #expect(plan.maximumRisk == .reversible)
    #expect(!plan.diff.contains { $0.path == "spec.power" })
}

@Test func missingApplicationSourceDoesNotPlanLaunch() throws {
    let current = SimulatorSnapshot(device: device, state: .init(power: .booted))
    let profile = SimulatorStateProfile(
        metadata: .init(name: "missing-source"),
        target: .init(udid: device.udid),
        spec: .init(applications: [
            .init(bundleIdentifier: "com.example.missing", running: true),
        ])
    )

    let plan = try StatePlanner().makePlan(profile: profile, current: current)
    #expect(!plan.operations.contains { $0.action == .launchApplication })
    #expect(plan.warnings == ["Cannot install com.example.missing: sourcePath is missing."])
}

@Test func eraseIsDestructiveAndFirst() throws {
    let current = SimulatorSnapshot(device: device, state: .init(power: .shutdown))
    let profile = SimulatorStateProfile(
        metadata: .init(name: "clean"),
        target: .init(udid: device.udid),
        spec: .init(power: .booted, eraseBeforeApply: true)
    )

    let plan = try StatePlanner().makePlan(profile: profile, current: current)
    #expect(plan.operations.first?.action == .erase)
    #expect(plan.operations.first?.risk == .destructive)
    #expect(plan.maximumRisk == .destructive)
}

@Test func unsupportedCapabilitiesAreReportedNotApplied() throws {
    let current = SimulatorSnapshot(
        device: device,
        state: .init(power: .booted),
        capabilities: [
            "power": .init(support: .exact, readable: true, writable: true),
            "preferences": .init(
                support: .unsupported,
                readable: false,
                writable: false,
                note: "Unavailable on this runtime"
            ),
        ]
    )
    let profile = SimulatorStateProfile(
        metadata: .init(name: "unsupported"),
        target: .init(udid: device.udid),
        spec: .init(preferences: [.init(domain: "x", key: "y", value: .integer(1))])
    )

    let plan = try StatePlanner().makePlan(profile: profile, current: current)
    #expect(plan.diff.contains { $0.kind == .unsupported })
    #expect(!plan.operations.contains { $0.action == .setPreference })
    #expect(plan.warnings == ["Skipped preferences: Unavailable on this runtime"])
}
