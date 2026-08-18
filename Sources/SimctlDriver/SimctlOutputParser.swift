import Foundation
import SimulatorStateCore

enum SimctlOutputParser {
    static func inventory(data: Data, developerDirectory: String?) throws -> SimulatorInventory {
        let decoded: ListPayload
        do {
            decoded = try JSONDecoder().decode(ListPayload.self, from: data)
        } catch {
            throw SimctlDriverError.malformedOutput(error.localizedDescription)
        }

        let runtimes = decoded.runtimes.map {
            SimulatorRuntime(
                identifier: $0.identifier,
                name: $0.name,
                version: $0.version,
                isAvailable: $0.isAvailable ?? true
            )
        }.sorted { $0.identifier < $1.identifier }

        let devices = decoded.devices.flatMap { runtime, devices in
            devices.map {
                SimulatorDevice(
                    udid: $0.udid,
                    name: $0.name,
                    state: SimulatorDeviceState(rawValue: $0.state) ?? .unknown,
                    runtimeIdentifier: runtime,
                    isAvailable: $0.isAvailable ?? true,
                    dataPath: $0.dataPath
                )
            }
        }.sorted {
            ($0.runtimeIdentifier, $0.name, $0.udid) < ($1.runtimeIdentifier, $1.name, $1.udid)
        }

        return SimulatorInventory(
            developerDirectory: developerDirectory,
            runtimes: runtimes,
            devices: devices
        )
    }

    static func applications(data: Data) throws -> [InstalledApplication] {
        let raw: Any
        if let json = try? JSONSerialization.jsonObject(with: data) {
            raw = json
        } else {
            do {
                raw = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            } catch {
                throw SimctlDriverError.malformedOutput("listapps is neither JSON nor a property list")
            }
        }

        guard let root = raw as? [String: Any] else {
            throw SimctlDriverError.malformedOutput("listapps root must be an object")
        }
        let applicationsObject = (root["apps"] as? [String: Any]) ?? root
        return applicationsObject.compactMap { key, rawValue in
            guard let value = rawValue as? [String: Any] else { return nil }
            let bundleIdentifier = value["CFBundleIdentifier"] as? String ?? key
            let bundlePath = value["Bundle"] as? String
                ?? value["BundlePath"] as? String
                ?? value["Path"] as? String
            return InstalledApplication(bundleIdentifier: bundleIdentifier, bundlePath: bundlePath)
        }.sorted { $0.bundleIdentifier < $1.bundleIdentifier }
    }
}

private struct ListPayload: Decodable {
    let runtimes: [RuntimePayload]
    let devices: [String: [DevicePayload]]
}

private struct RuntimePayload: Decodable {
    let identifier: String
    let name: String
    let version: String?
    let isAvailable: Bool?
}

private struct DevicePayload: Decodable {
    let udid: String
    let name: String
    let state: String
    let isAvailable: Bool?
    let dataPath: String?
}

