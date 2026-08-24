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

@Test func valuesUnsupportedByDefaultsAndStatusBarAreRejected() {
    let invalidPreference = SimulatorStateProfile(
        metadata: .init(name: "invalid-preference"),
        target: .init(udid: device.udid),
        spec: .init(preferences: [
            .init(domain: "x", key: "y", value: .object(["nested": .bool(true)])),
        ])
    )
    #expect(throws: StateCoreError.self) { try invalidPreference.validate() }

    let invalidStatusBar = SimulatorStateProfile(
        metadata: .init(name: "invalid-status"),
        target: .init(udid: device.udid),
        spec: .init(statusBar: ["bad_key": .array([.string("x")])])
    )
    #expect(throws: StateCoreError.self) { try invalidStatusBar.validate() }
}

@Test func profileDecoderAppliesSafeDefaults() throws {
    let json = #"""
    {
      "apiVersion": "awesome-ios-sim/v1alpha1",
      "kind": "SimulatorState",
      "metadata": { "name": "minimal" },
      "target": { "udid": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE" },
      "spec": {
        "applications": [{ "bundleIdentifier": "com.example.app" }]
      }
    }
    """#

    let profile = try StateCodec.decodeProfile(from: Data(json.utf8))
    #expect(profile.spec.power == .unchanged)
    #expect(!profile.spec.eraseBeforeApply)
    #expect(profile.spec.applications[0].presence == .present)
    #expect(profile.spec.applications[0].launchArguments.isEmpty)
}

@Test func profileDecoderRejectsUnknownFieldsAtEveryManagedLevel() {
    let documents = [
        #"{"apiVersion":"awesome-ios-sim/v1alpha1","kind":"SimulatorState","metadata":{"name":"x"},"target":{"udid":"DEVICE"},"spec":{},"typo":true}"#,
        #"{"apiVersion":"awesome-ios-sim/v1alpha1","kind":"SimulatorState","metadata":{"name":"x","typo":true},"target":{"udid":"DEVICE"},"spec":{}}"#,
        #"{"apiVersion":"awesome-ios-sim/v1alpha1","kind":"SimulatorState","metadata":{"name":"x"},"target":{"udid":"DEVICE","typo":true},"spec":{}}"#,
        #"{"apiVersion":"awesome-ios-sim/v1alpha1","kind":"SimulatorState","metadata":{"name":"x"},"target":{"udid":"DEVICE"},"spec":{"typo":true}}"#,
        #"{"apiVersion":"awesome-ios-sim/v1alpha1","kind":"SimulatorState","metadata":{"name":"x"},"target":{"udid":"DEVICE"},"spec":{"applications":[{"bundleIdentifier":"com.example","typo":true}]}}"#,
        #"{"apiVersion":"awesome-ios-sim/v1alpha1","kind":"SimulatorState","metadata":{"name":"x"},"target":{"udid":"DEVICE"},"spec":{"preferences":[{"domain":"x","key":"y","value":true,"typo":true}]}}"#,
    ]

    for document in documents {
        #expect(throws: StateCoreError.self) {
            try StateCodec.decodeProfile(from: Data(document.utf8))
        }
    }
}

@Test func profileValidationMatchesPublishedNonEmptyConstraints() {
    let profiles = [
        SimulatorStateProfile(metadata: .init(name: ""), target: .init(udid: "DEVICE"), spec: .init()),
        SimulatorStateProfile(metadata: .init(name: "x"), target: .init(udid: ""), spec: .init()),
        SimulatorStateProfile(
            metadata: .init(name: "x"),
            target: .init(udid: "DEVICE"),
            spec: .init(applications: [.init(bundleIdentifier: "")])
        ),
        SimulatorStateProfile(
            metadata: .init(name: "x"),
            target: .init(udid: "DEVICE"),
            spec: .init(applications: [.init(bundleIdentifier: "com.example", sourcePath: "")])
        ),
        SimulatorStateProfile(
            metadata: .init(name: "x"),
            target: .init(udid: "DEVICE"),
            spec: .init(preferences: [.init(domain: "", key: "y", value: .bool(true))])
        ),
    ]

    for profile in profiles {
        #expect(throws: StateCoreError.self) { try profile.validate() }
    }
}

@Test func statusBarValidationMatchesPublicSimctlContract() throws {
    let valid = SimulatorStateProfile(
        metadata: .init(name: "valid-status"),
        target: .init(udid: "DEVICE"),
        spec: .init(statusBar: [
            "time": .string("09:41"),
            "dataNetwork": .string("5g"),
            "wifiBars": .integer(3),
            "cellularBars": .integer(4),
            "batteryState": .string("charged"),
            "batteryLevel": .integer(100),
        ])
    )
    try valid.validate()

    let invalidOverrides: [[String: JSONValue]] = [
        [:],
        ["unknown": .string("value")],
        ["wifiBars": .integer(4)],
        ["cellularBars": .integer(-1)],
        ["batteryLevel": .number(99.5)],
        ["batteryState": .string("full")],
        ["time": .integer(941)],
    ]
    for statusBar in invalidOverrides {
        let profile = SimulatorStateProfile(
            metadata: .init(name: "invalid-status"),
            target: .init(udid: "DEVICE"),
            spec: .init(statusBar: statusBar)
        )
        #expect(throws: StateCoreError.self) { try profile.validate() }
    }
}

@Test func layersComposeInOrderWithStableKeyedCollections() throws {
    let profile = SimulatorStateProfile(
        metadata: .init(name: "composed"),
        target: .init(udid: "DEVICE"),
        spec: .init(
            power: .unchanged,
            applications: [
                .init(bundleIdentifier: "com.example.z", running: false),
            ],
            preferences: [
                .init(domain: "com.example", key: "mode", value: .string("base")),
            ],
            statusBar: ["time": .string("12:00")]
        )
    )
    let layer = SimulatorStateLayer(
        metadata: .init(name: "ui-test-app"),
        spec: .init(
            power: .booted,
            applications: [
                .init(bundleIdentifier: "com.example.a", running: true),
                .init(bundleIdentifier: "com.example.z", presence: .absent),
            ],
            preferences: [
                .init(domain: "com.example", key: "mode", value: .string("layer")),
                .init(domain: "com.example", key: "onboarding", value: .bool(false)),
            ],
            statusBar: ["operatorName": .string("Example")]
        )
    )

    let composed = try SimulatorStateComposer().compose(
        profile: profile,
        overlays: [.preset("clean-status-bar"), .layer(layer), .preset("shutdown")]
    )

    #expect(composed.metadata == profile.metadata)
    #expect(composed.target == profile.target)
    #expect(composed.spec.power == .shutdown)
    #expect(composed.spec.applications.map(\.bundleIdentifier) == ["com.example.a", "com.example.z"])
    #expect(composed.spec.applications[1].presence == .absent)
    #expect(composed.spec.preferences.map(\.identifier) == [
        "com.example::mode", "com.example::onboarding",
    ])
    #expect(composed.spec.preferences[0].value == .string("layer"))
    #expect(composed.spec.statusBar?["time"] == .string("09:41"))
    #expect(composed.spec.statusBar?["operatorName"] == .string("Example"))
    #expect(composed.spec.statusBar?["batteryLevel"] == .integer(100))
}

@Test func layerCodecIsStrictAndRequiresManagedState() throws {
    let valid = #"{"apiVersion":"awesome-ios-sim/v1alpha1","kind":"SimulatorStateLayer","metadata":{"name":"boot"},"spec":{"power":"booted"}}"#
    let layer = try StateCodec.decodeLayer(from: Data(valid.utf8))
    #expect(layer.spec.power == .booted)

    let invalidDocuments = [
        #"{"apiVersion":"awesome-ios-sim/v1alpha1","kind":"SimulatorStateLayer","metadata":{"name":"empty"},"spec":{}}"#,
        #"{"apiVersion":"awesome-ios-sim/v1alpha1","kind":"SimulatorStateLayer","metadata":{"name":"typo"},"spec":{"powers":"booted"}}"#,
        #"{"apiVersion":"awesome-ios-sim/v1alpha1","kind":"SimulatorStateLayer","metadata":{"name":"bad"},"target":{"udid":"DEVICE"},"spec":{"power":"booted"}}"#,
    ]
    for document in invalidDocuments {
        #expect(throws: Error.self) { try StateCodec.decodeLayer(from: Data(document.utf8)) }
    }
}

@Test func unknownPresetReportsAvailableNames() {
    #expect(throws: StateCoreError.unknownPreset("missing")) {
        try SimulatorStatePresetCatalog.layer(named: "missing")
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

@Test func eraseShutsDownFirstAndRestoresUnchangedPower() throws {
    let bootedDevice = SimulatorDevice(
        udid: device.udid,
        name: device.name,
        state: .booted,
        runtimeIdentifier: device.runtimeIdentifier
    )
    let current = SimulatorSnapshot(device: bootedDevice, state: .init(power: .booted))
    let profile = SimulatorStateProfile(
        metadata: .init(name: "clean-and-restore"),
        target: .init(udid: device.udid),
        spec: .init(power: .unchanged, eraseBeforeApply: true)
    )

    let plan = try StatePlanner().makePlan(profile: profile, current: current)
    #expect(plan.operations.map(\.action) == [.shutdown, .erase, .boot])
    #expect(!plan.diff.contains { $0.path == "spec.power" })
}

@Test func transientBootRestoresOriginalShutdownForUnchangedPower() throws {
    let current = SimulatorSnapshot(device: device, state: .init(power: .shutdown))
    let profile = SimulatorStateProfile(
        metadata: .init(name: "temporary-boot"),
        target: .init(udid: device.udid),
        spec: .init(
            power: .unchanged,
            preferences: [.init(domain: "x", key: "y", value: .integer(1))]
        )
    )

    let plan = try StatePlanner().makePlan(profile: profile, current: current)
    #expect(plan.operations.map(\.action) == [.boot, .setPreference, .shutdown])
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
