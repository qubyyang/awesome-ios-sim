import Foundation

/// Enforces the JSON document shape that Codable intentionally ignores.
/// Semantic value constraints remain in `SimulatorStateProfile.validate()`.
enum ProfileDocumentValidator {
    static func validate(_ data: Data) throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case let .object(root) = value else {
            throw StateCoreError.invalidProfile("document root must be an object")
        }

        try rejectUnknownKeys(
            root,
            allowed: ["apiVersion", "kind", "metadata", "target", "spec"],
            path: "$"
        )
        try validateObject(root["metadata"], allowed: ["name", "description"], path: "metadata")
        try validateObject(root["target"], allowed: ["udid", "name", "runtime"], path: "target")

        guard case let .object(spec)? = root["spec"] else { return }
        try rejectUnknownKeys(
            spec,
            allowed: ["power", "eraseBeforeApply", "applications", "preferences", "statusBar"],
            path: "spec"
        )

        if case let .array(applications)? = spec["applications"] {
            for (index, application) in applications.enumerated() {
                try validateObject(
                    application,
                    allowed: ["bundleIdentifier", "sourcePath", "presence", "running", "launchArguments"],
                    path: "spec.applications[\(index)]"
                )
            }
        }

        if case let .array(preferences)? = spec["preferences"] {
            for (index, preference) in preferences.enumerated() {
                try validateObject(
                    preference,
                    allowed: ["domain", "key", "value"],
                    path: "spec.preferences[\(index)]"
                )
            }
        }
    }

    private static func validateObject(
        _ value: JSONValue?,
        allowed: Set<String>,
        path: String
    ) throws {
        guard case let .object(object)? = value else { return }
        try rejectUnknownKeys(object, allowed: allowed, path: path)
    }

    private static func rejectUnknownKeys(
        _ object: [String: JSONValue],
        allowed: Set<String>,
        path: String
    ) throws {
        let unknown = Set(object.keys).subtracting(allowed).sorted()
        guard unknown.isEmpty else {
            throw StateCoreError.invalidProfile(
                "unknown field\(unknown.count == 1 ? "" : "s") at \(path): \(unknown.joined(separator: ", "))"
            )
        }
    }
}
