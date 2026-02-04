import Foundation
import SweetDeckDomain
import SweetDeckInfra

public struct SweetDeckXcodeProjectListing: Codable, Sendable {
    public var schemes: [String]
    public var targets: [String]?
    public var configurations: [String]?
}

public struct SweetDeckBuildAppPath: Codable, Sendable {
    public var appPath: String
    public var bundleIdentifier: String?

    public init(appPath: String, bundleIdentifier: String?) {
        self.appPath = appPath
        self.bundleIdentifier = bundleIdentifier
    }
}

public protocol SweetDeckXcodeBuilding {
    func list(project: SweetDeckProjectRef, cwd: String) throws -> SweetDeckXcodeProjectListing
    func build(context: SweetDeckResolvedContext, extraArgs: [String], stream: Bool, cwd: String) throws -> SweetDeckRunResult
    func clean(context: SweetDeckResolvedContext, extraArgs: [String], stream: Bool, cwd: String) throws -> SweetDeckRunResult
    func test(context: SweetDeckResolvedContext, extraArgs: [String], stream: Bool, cwd: String) throws -> SweetDeckRunResult
    func showBuildSettingsJSON(context: SweetDeckResolvedContext, extraArgs: [String], cwd: String) throws -> Any
    func resolvePackageDependencies(project: SweetDeckProjectRef, cwd: String) throws -> SweetDeckRunResult
}

public final class SweetDeckXcodebuildClient: SweetDeckXcodeBuilding {
    private let process: SweetDeckProcessRunning
    private let console: SweetDeckConsole

    public init(process: SweetDeckProcessRunning, console: SweetDeckConsole) {
        self.process = process
        self.console = console
    }

    public func list(project: SweetDeckProjectRef, cwd: String) throws -> SweetDeckXcodeProjectListing {
        let args = projectArgs(project) + ["-list", "-json"]
        let result = try process.runCapture(SweetDeckCommand(executable: "/usr/bin/xcodebuild", arguments: args), cwd: cwd)
        guard result.exitCode == 0 else {
            throw SweetDeckError(code: .xcodebuildFailed, message: "xcodebuild -list failed", details: ["exit": "\(result.exitCode)"])
        }

        let any = try SweetDeckJSON.parseAny(from: result.stdout)
        let schemes = SweetDeckAnyJSONSearch.findStringArray(any, rootKeys: ["workspace", "project"], nestedKey: "schemes") ?? []
        let targets = SweetDeckAnyJSONSearch.findStringArray(any, rootKeys: ["workspace", "project"], nestedKey: "targets")
        let configs = SweetDeckAnyJSONSearch.findStringArray(any, rootKeys: ["workspace", "project"], nestedKey: "configurations")
        return SweetDeckXcodeProjectListing(schemes: schemes, targets: targets, configurations: configs)
    }

    public func build(context: SweetDeckResolvedContext, extraArgs: [String], stream: Bool, cwd: String) throws -> SweetDeckRunResult {
        try runXcodebuild(context: context, action: "build", extraArgs: extraArgs, stream: stream, cwd: cwd)
    }

    public func clean(context: SweetDeckResolvedContext, extraArgs: [String], stream: Bool, cwd: String) throws -> SweetDeckRunResult {
        try runXcodebuild(context: context, action: "clean", extraArgs: extraArgs, stream: stream, cwd: cwd)
    }

    public func test(context: SweetDeckResolvedContext, extraArgs: [String], stream: Bool, cwd: String) throws -> SweetDeckRunResult {
        try runXcodebuild(context: context, action: "test", extraArgs: extraArgs, stream: stream, cwd: cwd)
    }

    public func showBuildSettingsJSON(context: SweetDeckResolvedContext, extraArgs: [String], cwd: String) throws -> Any {
        let args = baseArgs(context) + ["-showBuildSettings", "-json"] + extraArgs
        console.debug("xcodebuild \(args.joined(separator: " "))")
        let result = try process.runCapture(SweetDeckCommand(executable: "/usr/bin/xcodebuild", arguments: args), cwd: cwd)
        guard result.exitCode == 0 else {
            throw SweetDeckError(code: .xcodebuildFailed, message: "xcodebuild -showBuildSettings failed", details: ["exit": "\(result.exitCode)"])
        }
        return try SweetDeckJSON.parseAny(from: result.stdout)
    }

    public func resolvePackageDependencies(project: SweetDeckProjectRef, cwd: String) throws -> SweetDeckRunResult {
        let args = projectArgs(project) + ["-resolvePackageDependencies"]
        console.debug("xcodebuild \(args.joined(separator: " "))")
        let result = try process.runStreaming(SweetDeckCommand(executable: "/usr/bin/xcodebuild", arguments: args), cwd: cwd, streamToStdout: true, streamToStderr: true)
        guard result.exitCode == 0 else {
            throw SweetDeckError(code: .xcodebuildFailed, message: "xcodebuild -resolvePackageDependencies failed", details: ["exit": "\(result.exitCode)"])
        }
        return result
    }

    private func runXcodebuild(context: SweetDeckResolvedContext, action: String, extraArgs: [String], stream: Bool, cwd: String) throws -> SweetDeckRunResult {
        let args = baseArgs(context) + context.xcodebuildArguments + extraArgs + [action]
        console.debug("xcodebuild \(args.joined(separator: " "))")
        let result: SweetDeckRunResult
        if stream {
            result = try process.runStreaming(
                SweetDeckCommand(executable: "/usr/bin/xcodebuild", arguments: args),
                cwd: cwd,
                streamToStdout: true,
                streamToStderr: true
            )
        } else {
            result = try process.runCapture(SweetDeckCommand(executable: "/usr/bin/xcodebuild", arguments: args), cwd: cwd)
        }
        guard result.exitCode == 0 else {
            if !stream { writeFailureOutput(result) }
            throw SweetDeckError(code: .xcodebuildFailed, message: "xcodebuild \(action) failed", details: ["exit": "\(result.exitCode)"])
        }
        return result
    }

    private func writeFailureOutput(_ result: SweetDeckRunResult) {
        let stderr = FileHandle.standardError
        if !result.stdout.isEmpty { stderr.write(result.stdout) }
        if !result.stderr.isEmpty { stderr.write(result.stderr) }
    }

    private func projectArgs(_ project: SweetDeckProjectRef) -> [String] {
        switch project.type ?? inferType(from: project.path) {
        case .xcworkspace:
            return ["-workspace", project.path]
        case .xcodeproj:
            return ["-project", project.path]
        }
    }

    private func inferType(from path: String) -> SweetDeckProjectType {
        if path.hasSuffix(".xcworkspace") { return .xcworkspace }
        return .xcodeproj
    }

    private func baseArgs(_ context: SweetDeckResolvedContext) -> [String] {
        projectArgs(context.project) + [
            "-scheme", context.scheme,
            "-configuration", context.configuration,
            "-destination", context.destination,
            "-derivedDataPath", context.derivedDataPath,
        ]
    }
}
