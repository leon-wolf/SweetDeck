import Foundation
import SweetDeckDomain
import SweetDeckInfra

public protocol SweetDeckDeviceControlling {
    func listDevices(cwd: String) throws -> Any
    func installApp(device: String, appPath: String, cwd: String) throws -> Any
    func uninstallApp(device: String, bundleId: String, cwd: String) throws -> Any
    func launchApp(device: String, bundleId: String, args: [String], env: [String: String], cwd: String) throws -> Any
    func terminate(device: String, pid: Int, kill: Bool, cwd: String) throws -> Any
}

public final class SweetDeckDevicectlClient: SweetDeckDeviceControlling {
    private let process: SweetDeckProcessRunning
    private let console: SweetDeckConsole

    public init(process: SweetDeckProcessRunning, console: SweetDeckConsole) {
        self.process = process
        self.console = console
    }

    public func listDevices(cwd: String) throws -> Any {
        try runDevicectlJSON(args: ["list", "devices"], cwd: cwd)
    }

    public func installApp(device: String, appPath: String, cwd: String) throws -> Any {
        try runDevicectlJSON(args: ["device", "install", "app", "--device", device, appPath], cwd: cwd)
    }

    public func uninstallApp(device: String, bundleId: String, cwd: String) throws -> Any {
        try runDevicectlJSON(args: ["device", "uninstall", "app", "--device", device, bundleId], cwd: cwd)
    }

    public func launchApp(device: String, bundleId: String, args: [String], env: [String: String], cwd: String) throws -> Any {
        var devArgs = ["device", "process", "launch", "--device", device]
        if !env.isEmpty {
            let envJSON = try SweetDeckJSON.encodePretty(env)
            let envStr = String(data: envJSON, encoding: .utf8) ?? "{}"
            devArgs += ["--environment-variables", envStr]
        }
        devArgs.append(bundleId)
        devArgs += args
        return try runDevicectlJSON(args: devArgs, cwd: cwd)
    }

    public func terminate(device: String, pid: Int, kill: Bool, cwd: String) throws -> Any {
        var args = ["device", "process", "terminate", "--device", device, "--pid", "\(pid)"]
        if kill { args.append("--kill") }
        return try runDevicectlJSON(args: args, cwd: cwd)
    }

    private func runDevicectlJSON(args: [String], cwd: String) throws -> Any {
        return try SweetDeckTempFiles.withTemporaryFile(prefix: "sweetdeck-devicectl-", suffix: ".json") { jsonPath in
            let fullArgs = ["devicectl", "--json-output", jsonPath] + args
            console.debug("xcrun \(fullArgs.joined(separator: " "))")
            let result = try process.runStreaming(
                SweetDeckCommand(executable: "/usr/bin/xcrun", arguments: fullArgs),
                cwd: cwd,
                streamToStdout: console.outputFormat == .human,
                streamToStderr: console.outputFormat == .human
            )
            guard result.exitCode == 0 else {
                throw SweetDeckError(code: .devicectlFailed, message: "devicectl failed", details: ["exit": "\(result.exitCode)"])
            }
            let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
            return try SweetDeckJSON.parseAny(from: data)
        }
    }
}
