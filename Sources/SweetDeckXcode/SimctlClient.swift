import Foundation
import SweetDeckDomain
import SweetDeckInfra

public protocol SweetDeckSimulatorControlling {
    func listDevices(cwd: String) throws -> [SweetDeckSimulatorDevice]
    func resolveUDID(destination: String, cwd: String) throws -> String
    func installApp(simulatorUDID: String, appPath: String, cwd: String) throws -> SweetDeckRunResult
    func launchApp(simulatorUDID: String, bundleId: String, args: [String], env: [String: String], cwd: String) throws -> SweetDeckRunResult
    func terminateApp(simulatorUDID: String, bundleId: String, cwd: String) throws -> SweetDeckRunResult
    func listApps(simulatorUDID: String, cwd: String) throws -> SweetDeckRunResult
    func uninstallApp(simulatorUDID: String, bundleId: String, cwd: String) throws -> SweetDeckRunResult
    func boot(simulator: String, cwd: String) throws -> SweetDeckRunResult
    func shutdown(simulator: String, cwd: String) throws -> SweetDeckRunResult
    func create(name: String, deviceType: String, runtime: String, cwd: String) throws -> SweetDeckRunResult
    func delete(simulator: String, cwd: String) throws -> SweetDeckRunResult
    func deleteUnavailable(cwd: String) throws -> SweetDeckRunResult
    func listDeviceTypes(cwd: String) throws -> SweetDeckRunResult
    func listRuntimes(cwd: String) throws -> SweetDeckRunResult
    func setLocation(simulator: String, latitude: String, longitude: String, cwd: String) throws -> SweetDeckRunResult
    func addMedia(simulator: String, paths: [String], cwd: String) throws -> SweetDeckRunResult
    func logStream(simulatorUDID: String, style: String, level: String, predicate: String?, cwd: String) throws -> SweetDeckRunResult
}

public final class SweetDeckSimctlClient: SweetDeckSimulatorControlling {
    private let process: SweetDeckProcessRunning
    private let console: SweetDeckConsole

    public init(process: SweetDeckProcessRunning, console: SweetDeckConsole) {
        self.process = process
        self.console = console
    }

    public func listDevices(cwd: String) throws -> [SweetDeckSimulatorDevice] {
        let result = try runSimctl(args: ["list", "-j", "devices"], cwd: cwd, stream: false)
        guard result.exitCode == 0 else {
            throw SweetDeckError(code: .simctlFailed, message: "simctl list devices failed", details: ["exit": "\(result.exitCode)"])
        }
        let any = try SweetDeckJSON.parseAny(from: result.stdout)
        guard let dict = any as? [String: Any], let devicesByRuntime = dict["devices"] as? [String: Any] else {
            return []
        }

        var devices: [SweetDeckSimulatorDevice] = []
        for (runtime, arrAny) in devicesByRuntime {
            guard let arr = arrAny as? [[String: Any]] else { continue }
            for entry in arr {
                guard ifAvailable(entry) else { continue }
                let name = entry["name"] as? String ?? "Unknown"
                let udid = entry["udid"] as? String ?? ""
                let state = entry["state"] as? String
                let isAvailable = entry["isAvailable"] as? Bool
                devices.append(SweetDeckSimulatorDevice(name: name, udid: udid, state: state, isAvailable: isAvailable, runtime: runtime))
            }
        }
        return devices
    }

    public func resolveUDID(destination: String, cwd: String) throws -> String {
        if SweetDeckDestinationResolver.looksLikeUUID(destination) { return destination }
        if let id = SweetDeckDestinationResolver.extractID(destination: destination), SweetDeckDestinationResolver.looksLikeUUID(id) { return id }
        guard let name = SweetDeckDestinationResolver.extractSimulatorName(destination: destination) else {
            throw SweetDeckError(code: .config, message: "Could not determine simulator from destination", details: ["destination": destination])
        }
        let devices = try listDevices(cwd: cwd)
        if let exact = devices.first(where: { $0.name == name }) { return exact.udid }
        if let contains = devices.first(where: { $0.name.localizedCaseInsensitiveContains(name) }) { return contains.udid }
        throw SweetDeckError(code: .simctlFailed, message: "Simulator not found", details: ["name": name])
    }

    public func installApp(simulatorUDID: String, appPath: String, cwd: String) throws -> SweetDeckRunResult {
        let result = try runSimctl(args: ["install", simulatorUDID, appPath], cwd: cwd, stream: true)
        guard result.exitCode == 0 else {
            throw SweetDeckError(code: .simctlFailed, message: "simctl install failed", details: ["exit": "\(result.exitCode)"])
        }
        return result
    }

    public func launchApp(simulatorUDID: String, bundleId: String, args: [String], env: [String: String], cwd: String) throws -> SweetDeckRunResult {
        var envVars: [String: String] = [:]
        for (k, v) in env { envVars["SIMCTL_CHILD_\(k)"] = v }
        let result = try runSimctl(args: ["launch", simulatorUDID, bundleId] + args, cwd: cwd, stream: true, env: envVars)
        guard result.exitCode == 0 else {
            throw SweetDeckError(code: .simctlFailed, message: "simctl launch failed", details: ["exit": "\(result.exitCode)"])
        }
        return result
    }

    public func terminateApp(simulatorUDID: String, bundleId: String, cwd: String) throws -> SweetDeckRunResult {
        let result = try runSimctl(args: ["terminate", simulatorUDID, bundleId], cwd: cwd, stream: true)
        guard result.exitCode == 0 else {
            throw SweetDeckError(code: .simctlFailed, message: "simctl terminate failed", details: ["exit": "\(result.exitCode)"])
        }
        return result
    }

    public func listApps(simulatorUDID: String, cwd: String) throws -> SweetDeckRunResult {
        try runSimctl(args: ["listapps", simulatorUDID], cwd: cwd, stream: true)
    }

    public func uninstallApp(simulatorUDID: String, bundleId: String, cwd: String) throws -> SweetDeckRunResult {
        try runSimctl(args: ["uninstall", simulatorUDID, bundleId], cwd: cwd, stream: true)
    }

    public func boot(simulator: String, cwd: String) throws -> SweetDeckRunResult {
        try runSimctl(args: ["boot", simulator], cwd: cwd, stream: true)
    }

    public func shutdown(simulator: String, cwd: String) throws -> SweetDeckRunResult {
        try runSimctl(args: ["shutdown", simulator], cwd: cwd, stream: true)
    }

    public func create(name: String, deviceType: String, runtime: String, cwd: String) throws -> SweetDeckRunResult {
        try runSimctl(args: ["create", name, deviceType, runtime], cwd: cwd, stream: true)
    }

    public func delete(simulator: String, cwd: String) throws -> SweetDeckRunResult {
        try runSimctl(args: ["delete", simulator], cwd: cwd, stream: true)
    }

    public func deleteUnavailable(cwd: String) throws -> SweetDeckRunResult {
        try runSimctl(args: ["delete", "unavailable"], cwd: cwd, stream: true)
    }

    public func listDeviceTypes(cwd: String) throws -> SweetDeckRunResult {
        try runSimctl(args: ["list", "-j", "devicetypes"], cwd: cwd, stream: true)
    }

    public func listRuntimes(cwd: String) throws -> SweetDeckRunResult {
        try runSimctl(args: ["list", "-j", "runtimes"], cwd: cwd, stream: true)
    }

    public func setLocation(simulator: String, latitude: String, longitude: String, cwd: String) throws -> SweetDeckRunResult {
        try runSimctl(args: ["location", simulator, "set", latitude, longitude], cwd: cwd, stream: true)
    }

    public func addMedia(simulator: String, paths: [String], cwd: String) throws -> SweetDeckRunResult {
        try runSimctl(args: ["addmedia", simulator] + paths, cwd: cwd, stream: true)
    }

    public func logStream(simulatorUDID: String, style: String, level: String, predicate: String?, cwd: String) throws -> SweetDeckRunResult {
        var args = ["spawn", simulatorUDID, "log", "stream", "--style", style, "--level", level]
        if let predicate, !predicate.isEmpty {
            args += ["--predicate", predicate]
        }
        return try runSimctl(args: args, cwd: cwd, stream: true)
    }

    private func runSimctl(args: [String], cwd: String, stream: Bool, env: [String: String] = [:]) throws -> SweetDeckRunResult {
        console.debug("xcrun simctl \(args.joined(separator: " "))")
        return try process.runStreaming(
            SweetDeckCommand(executable: "/usr/bin/xcrun", arguments: ["simctl"] + args, environment: env),
            cwd: cwd,
            streamToStdout: stream,
            streamToStderr: stream
        )
    }

    private func ifAvailable(_ entry: [String: Any]) -> Bool {
        if let isAvailable = entry["isAvailable"] as? Bool { return isAvailable }
        if let availability = entry["availability"] as? String {
            return availability.contains("available") && !availability.contains("unavailable")
        }
        return true
    }
}
