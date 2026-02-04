import Foundation
import SweetDeckDomain
import SweetDeckInfra
import SweetDeckUseCases
import SweetDeckXcode
import ArgumentParser

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create .sweetdeck/config.json and .sweetdeck/ directory.")

    @OptionGroup var global: GlobalOptions

    @Option(name: .customLong("project-path"), help: "Project path (.xcworkspace or .xcodeproj).")
    var projectPath: String?

    @Option(name: .customLong("project-type"), help: "Project type.")
    var projectType: ProjectTypeArg?

    @Option(name: .customLong("schemes"), parsing: .unconditionalSingleValue, help: "Schemes list (repeatable or comma-separated).")
    var schemes: [String] = []

    @Option(help: "Build configuration.")
    var configuration: String = "Debug"

    @Option(help: "Destination string for xcodebuild.")
    var destination: String?

    @Option(name: .customLong("derived-data-path"), help: "Derived data path.")
    var derivedDataPath: String = ".sweetdeck/DerivedData"

    @Option(name: .customLong("xcodebuild-arg"), parsing: .unconditionalSingleValue, help: "Additional xcodebuild argument (repeatable).")
    var xcodebuildArg: [String] = []

    @Option(name: .customLong("bundle-id"), help: "Bundle identifier (appLaunch.bundleIdentifier).")
    var bundleId: String?

    @Option(name: .customLong("app-arg"), parsing: .unconditionalSingleValue, help: "App argument (repeatable).")
    var appArg: [String] = []

    @Option(name: .customLong("app-env"), parsing: .unconditionalSingleValue, help: "App environment variable KEY=VALUE (repeatable).")
    var appEnv: [String] = []

    @Flag(name: .customLong("non-interactive"), help: "Fail instead of prompting when missing values.")
    var nonInteractive: Bool = false

    func run() throws {
        let runtime = global.makeRuntime()
        let usecases = SweetDeckUseCases(runtime: runtime)

        var env: [String: String] = [:]
        for kv in appEnv {
            let parts = kv.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count != 2 { throw ValidationError("--app-env must be KEY=VALUE") }
            env[parts[0]] = parts[1]
        }
        let schemesList = schemes
            .flatMap { $0.split(separator: ",").map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        do {
            let ctx = try usecases.initProject(
                cwd: runtime.configLoaderForcedCwd(),
                options: SweetDeckInitOptions(
                    projectPath: projectPath,
                    projectType: projectType?.domain,
                    scheme: global.scheme,
                    schemes: schemesList,
                    pickScheme: global.pickScheme,
                    configuration: configuration,
                    destination: destination,
                    derivedDataPath: derivedDataPath,
                    xcodebuildArgs: xcodebuildArg,
                    bundleId: bundleId,
                    appArgs: appArg,
                    appEnv: env,
                    nonInteractive: nonInteractive
                )
            )

            if runtime.console.outputFormat == .json {
                try finishJSONSuccess("Initialized", details: ctx)
            }
        } catch {
            let e = mapError(error)
            if runtime.console.outputFormat == .json { try finishJSONError(e) }
            runtime.console.error(e.description)
            throw ExitCode(Int32(e.code.rawValue))
        }
    }
}

struct Context: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print resolved context.")

    @OptionGroup var global: GlobalOptions

    @Flag(help: "Refresh discovered schemes and simulator devices.")
    var refresh: Bool = false

    func run() throws {
        let runtime = global.makeRuntime()
        let usecases = SweetDeckUseCases(runtime: runtime)
        do {
            let overrides = try schemeOverrides(runtime: runtime, usecases: usecases, global: global)
            let (ctx, schemes, destinations) = try usecases.context(cwd: runtime.configLoaderForcedCwd(), refresh: refresh, overrides: overrides)
            if runtime.console.outputFormat == .json {
                struct Details: Encodable { var resolvedConfig: SweetDeckResolvedContext; var discoveredSchemes: [String]?; var discoveredDestinations: AnyEncodable? }
                try finishJSONSuccess("OK", details: Details(resolvedConfig: ctx, discoveredSchemes: schemes, discoveredDestinations: destinations.map(AnyEncodable.init)))
            }

            runtime.console.info("Config: \(ctx.configPath ?? "n/a") (from: \(ctx.loadedFrom ?? "n/a"))")
            runtime.console.info("Project: \(ctx.project.path) (\(ctx.project.type?.rawValue ?? "auto"))")
            runtime.console.info("Scheme: \(ctx.scheme)")
            runtime.console.info("Configuration: \(ctx.configuration)")
            runtime.console.info("Destination: \(ctx.destination)")
            runtime.console.info("DerivedData: \(ctx.derivedDataPath)")
            runtime.console.info("BundleId: \(ctx.appLaunch.bundleIdentifier ?? "n/a")")
        } catch {
            let e = mapError(error)
            if runtime.console.outputFormat == .json { try finishJSONError(e) }
            runtime.console.error(e.description)
            throw ExitCode(Int32(e.code.rawValue))
        }
    }
}

struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run xcodebuild build.")

    @OptionGroup var global: GlobalOptions
    @Flag(name: .customLong("clean-first"), help: "Run xcodebuild clean before build.")
    var cleanFirst: Bool = false

    @Option(name: .customLong("xcarg"), parsing: .unconditionalSingleValue, help: "Extra xcodebuild args (repeatable).")
    var xcarg: [String] = []

    func run() throws {
        let runtime = global.makeRuntime()
        let usecases = SweetDeckUseCases(runtime: runtime)
        do {
            let overrides = try schemeOverrides(runtime: runtime, usecases: usecases, global: global)
            let result = try usecases.build(cwd: runtime.configLoaderForcedCwd(), overrides: overrides, cleanFirst: cleanFirst, extraArgs: xcarg)
            if runtime.console.outputFormat == .json {
                struct Details: Encodable { var exit: Int32; var durationMs: Int64 }
                try finishJSONSuccess("Build succeeded", details: Details(exit: result.exitCode, durationMs: result.durationMs))
            }
        } catch {
            let e = mapError(error)
            if runtime.console.outputFormat == .json { try finishJSONError(e) }
            runtime.console.error(e.description)
            throw ExitCode(Int32(e.code.rawValue))
        }
    }
}

struct Clean: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run xcodebuild clean.")

    @OptionGroup var global: GlobalOptions

    @Flag(name: .customLong("delete-derived-data"), help: "Delete derived data directory after clean.")
    var deleteDerivedData: Bool = false

    @Option(name: .customLong("xcarg"), parsing: .unconditionalSingleValue, help: "Extra xcodebuild args (repeatable).")
    var xcarg: [String] = []

    func run() throws {
        let runtime = global.makeRuntime()
        let usecases = SweetDeckUseCases(runtime: runtime)
        do {
            let overrides = try schemeOverrides(runtime: runtime, usecases: usecases, global: global)
            try usecases.clean(cwd: runtime.configLoaderForcedCwd(), overrides: overrides, deleteDerivedData: deleteDerivedData, extraArgs: xcarg)
            if runtime.console.outputFormat == .json { try finishJSONSuccess("Cleaned") }
        } catch {
            let e = mapError(error)
            if runtime.console.outputFormat == .json { try finishJSONError(e) }
            runtime.console.error(e.description)
            throw ExitCode(Int32(e.code.rawValue))
        }
    }
}

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Build + install + launch.")

    @OptionGroup var global: GlobalOptions

    @Flag(name: .customLong("no-build"), help: "Skip build.")
    var noBuild: Bool = false

    @Flag(inversion: .prefixedNo, help: "Reinstall the app before launching.")
    var reinstall: Bool = true

    @Option(help: "Physical device identifier (name/udid). When set, uses devicectl.")
    var device: String?

    @Option(name: .customLong("bundle-id"), help: "Override bundle identifier.")
    var bundleId: String?

    @Option(name: .customLong("app-arg"), parsing: .unconditionalSingleValue, help: "App argument (repeatable).")
    var appArg: [String] = []

    @Option(name: .customLong("app-env"), parsing: .unconditionalSingleValue, help: "App environment variable KEY=VALUE (repeatable).")
    var appEnv: [String] = []

    @Option(name: .customLong("xcarg"), parsing: .unconditionalSingleValue, help: "Extra xcodebuild args (repeatable).")
    var xcarg: [String] = []

    func run() throws {
        let runtime = global.makeRuntime()
        let usecases = SweetDeckUseCases(runtime: runtime)
        do {
            var env: [String: String] = [:]
            for kv in appEnv {
                let parts = kv.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count != 2 { throw ValidationError("--app-env must be KEY=VALUE") }
                env[parts[0]] = parts[1]
            }

            let overrides = try schemeOverrides(runtime: runtime, usecases: usecases, global: global)
            let (app, details) = try usecases.run(
                cwd: runtime.configLoaderForcedCwd(),
                overrides: overrides,
                noBuild: noBuild,
                reinstall: reinstall,
                device: device,
                bundleIdOverride: bundleId,
                appArgsOverride: appArg,
                appEnvOverride: env,
                extraXcodeArgs: xcarg
            )
            if runtime.console.outputFormat == .json {
                struct Details: Encodable { var app: SweetDeckBuildAppPath; var toolOutput: AnyEncodable? }
                try finishJSONSuccess("Launched", details: Details(app: app, toolOutput: details.map(AnyEncodable.init)))
            }
            runtime.console.info("App: \(app.appPath)")
        } catch {
            let e = mapError(error)
            if runtime.console.outputFormat == .json { try finishJSONError(e) }
            runtime.console.error(e.description)
            throw ExitCode(Int32(e.code.rawValue))
        }
    }
}

struct Test: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run xcodebuild test.",
        subcommands: [Discover.self]
    )

    @OptionGroup var global: GlobalOptions

    @Flag(name: .customLong("clean-first"), help: "Run xcodebuild clean before testing.")
    var cleanFirst: Bool = false

    @Option(name: .customLong("only"), parsing: .unconditionalSingleValue, help: "Only testing specifier (repeatable).")
    var only: [String] = []

    @Option(name: .customLong("skip"), parsing: .unconditionalSingleValue, help: "Skip testing specifier (repeatable).")
    var skip: [String] = []

    @Option(name: .customLong("result-bundle-path"), help: "Result bundle path.")
    var resultBundlePath: String?

    @Option(name: .customLong("xcarg"), parsing: .unconditionalSingleValue, help: "Extra xcodebuild args (repeatable).")
    var xcarg: [String] = []

    func run() throws {
        let runtime = global.makeRuntime()
        let usecases = SweetDeckUseCases(runtime: runtime)
        do {
            let overrides = try schemeOverrides(runtime: runtime, usecases: usecases, global: global)
            let res = try usecases.test(
                cwd: runtime.configLoaderForcedCwd(),
                overrides: overrides,
                cleanFirst: cleanFirst,
                only: only,
                skip: skip,
                resultBundlePath: resultBundlePath,
                extraArgs: xcarg
            )
            if runtime.console.outputFormat == .json {
                struct Details: Encodable { var exit: Int32; var durationMs: Int64 }
                try finishJSONSuccess("Tests succeeded", details: Details(exit: res.exitCode, durationMs: res.durationMs))
            }
        } catch {
            let e = mapError(error)
            if runtime.console.outputFormat == .json { try finishJSONError(e) }
            runtime.console.error(e.description)
            throw ExitCode(Int32(e.code.rawValue))
        }
    }

    struct Discover: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Discover tests in the repo (XCTest and Swift Testing).")

        @OptionGroup var global: GlobalOptions

        @Option(help: "Root directory to scan.")
        var root: String?

        @Option(help: "Output format.")
        var format: DiscoverFormat = .human

        enum DiscoverFormat: String, ExpressibleByArgument, CaseIterable {
            case human
            case json
            case xcodebuildOnlyTesting = "xcodebuild-only-testing"
        }

        func run() throws {
            let runtime = global.makeRuntime()
            let usecases = SweetDeckUseCases(runtime: runtime)
            let cwd = runtime.configLoaderForcedCwd()
            let rootPath = root ?? cwd
            let tests = usecases.discoverTests(cwd: cwd, root: rootPath)

            switch format {
            case .json:
                let data = try SweetDeckJSON.encodePretty(tests)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write("\n".data(using: .utf8)!)
            case .xcodebuildOnlyTesting:
                // Best-effort: XCTest: Suite/testName, SwiftTesting: Suite/testName (may require adjustments).
                for t in tests {
                    FileHandle.standardOutput.write(("-only-testing:\(t.suite)/\(t.testName)\n").data(using: .utf8)!)
                }
                runtime.console.warn("Note: Specifiers are best-effort; adjust for target-qualified forms if needed.")
            case .human:
                var bySuite: [String: [SweetDeckDiscoveredTest]] = [:]
                for t in tests { bySuite[t.suite, default: []].append(t) }
                for suite in bySuite.keys.sorted() {
                    runtime.console.info("\(suite):")
                    for t in bySuite[suite]!.sorted(by: { $0.testName < $1.testName }) {
                        runtime.console.info("  - \(t.framework.rawValue): \(t.testName) (\(t.file):\(t.line))")
                    }
                }
            }
        }
    }
}

struct Logs: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stream simulator logs for the configured app (MVP).")

    @OptionGroup var global: GlobalOptions

    @Option(help: "Search string (filters by eventMessage).")
    var search: String?

    @Option(help: "Log style.")
    var style: String = "compact"

    @Option(help: "Log level.")
    var level: String = "debug"

    @Option(name: .customLong("bundle-id"), help: "Override bundle identifier.")
    var bundleId: String?

    func run() throws {
        let runtime = global.makeRuntime()
        let usecases = SweetDeckUseCases(runtime: runtime)
        do {
            let overrides = try schemeOverrides(runtime: runtime, usecases: usecases, global: global)
            try usecases.logs(cwd: runtime.configLoaderForcedCwd(), overrides: overrides, bundleIdOverride: bundleId, style: style, level: level, search: search)
        } catch {
            let e = mapError(error)
            if runtime.console.outputFormat == .json { try finishJSONError(e) }
            runtime.console.error(e.description)
            throw ExitCode(Int32(e.code.rawValue))
        }
    }
}

struct Stop: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Terminate the app on simulator or device.")

    @OptionGroup var global: GlobalOptions

    @Option(help: "Physical device identifier (name/udid). When set, uses devicectl.")
    var device: String?

    @Option(name: .customLong("bundle-id"), help: "Override bundle identifier.")
    var bundleId: String?

    @Option(help: "Process identifier (required for devices unless a prior launch was recorded).")
    var pid: Int?

    @Flag(help: "Use SIGKILL (device only).")
    var kill: Bool = false

    func run() throws {
        let runtime = global.makeRuntime()
        let usecases = SweetDeckUseCases(runtime: runtime)
        do {
            let overrides = try schemeOverrides(runtime: runtime, usecases: usecases, global: global)
            try usecases.stop(cwd: runtime.configLoaderForcedCwd(), overrides: overrides, device: device, bundleIdOverride: bundleId, pid: pid, kill: kill)
            if runtime.console.outputFormat == .json { try finishJSONSuccess("Stopped") }
        } catch {
            let e = mapError(error)
            if runtime.console.outputFormat == .json { try finishJSONError(e) }
            runtime.console.error(e.description)
            throw ExitCode(Int32(e.code.rawValue))
        }
    }
}

struct Apps: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage apps on simulators via simctl.",
        subcommands: [List.self, Install.self, Uninstall.self, Launch.self, Kill.self]
    )
    func run() throws {}

    struct SimulatorOpt: ParsableArguments {
        @Option(help: "Simulator UDID or name.")
        var simulator: String?
    }

    struct List: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @OptionGroup var sim: SimulatorOpt
        func run() throws {
            let runtime = global.makeRuntime()
            let cwd = runtime.configLoaderForcedCwd()
            do {
                let udid = try resolveSimulator(runtime: runtime, cwd: cwd, provided: sim.simulator)
                _ = try runtime.simctl.listApps(simulatorUDID: udid, cwd: cwd)
            } catch {
                let e = mapError(error)
                if runtime.console.outputFormat == .json { try finishJSONError(e) }
                runtime.console.error(e.description)
                throw ExitCode(Int32(e.code.rawValue))
            }
        }
    }

    struct Install: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @OptionGroup var sim: SimulatorOpt
        @Argument(help: "Path to .app bundle.")
        var path: String
        func run() throws {
            let runtime = global.makeRuntime()
            let cwd = runtime.configLoaderForcedCwd()
            do {
                let udid = try resolveSimulator(runtime: runtime, cwd: cwd, provided: sim.simulator)
                _ = try runtime.simctl.installApp(simulatorUDID: udid, appPath: runtime.fs.absolutePath(path, relativeTo: cwd), cwd: cwd)
            } catch {
                let e = mapError(error)
                if runtime.console.outputFormat == .json { try finishJSONError(e) }
                runtime.console.error(e.description)
                throw ExitCode(Int32(e.code.rawValue))
            }
        }
    }

    struct Uninstall: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @OptionGroup var sim: SimulatorOpt
        @Argument(help: "Bundle identifier.")
        var bundleId: String
        func run() throws {
            let runtime = global.makeRuntime()
            let cwd = runtime.configLoaderForcedCwd()
            do {
                let udid = try resolveSimulator(runtime: runtime, cwd: cwd, provided: sim.simulator)
                _ = try runtime.simctl.uninstallApp(simulatorUDID: udid, bundleId: bundleId, cwd: cwd)
            } catch {
                let e = mapError(error)
                if runtime.console.outputFormat == .json { try finishJSONError(e) }
                runtime.console.error(e.description)
                throw ExitCode(Int32(e.code.rawValue))
            }
        }
    }

    struct Launch: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @OptionGroup var sim: SimulatorOpt
        @Argument(help: "Bundle identifier.")
        var bundleId: String
        @Option(name: .customLong("app-arg"), parsing: .unconditionalSingleValue)
        var appArg: [String] = []
        @Option(name: .customLong("app-env"), parsing: .unconditionalSingleValue)
        var appEnv: [String] = []
        func run() throws {
            let runtime = global.makeRuntime()
            let cwd = runtime.configLoaderForcedCwd()
            do {
                var env: [String: String] = [:]
                for kv in appEnv {
                    let parts = kv.split(separator: "=", maxSplits: 1).map(String.init)
                    if parts.count != 2 { throw ValidationError("--app-env must be KEY=VALUE") }
                    env[parts[0]] = parts[1]
                }
                let udid = try resolveSimulator(runtime: runtime, cwd: cwd, provided: sim.simulator)
                _ = try runtime.simctl.launchApp(simulatorUDID: udid, bundleId: bundleId, args: appArg, env: env, cwd: cwd)
            } catch {
                let e = mapError(error)
                if runtime.console.outputFormat == .json { try finishJSONError(e) }
                runtime.console.error(e.description)
                throw ExitCode(Int32(e.code.rawValue))
            }
        }
    }

    struct Kill: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @OptionGroup var sim: SimulatorOpt
        @Argument(help: "Bundle identifier.")
        var bundleId: String
        func run() throws {
            let runtime = global.makeRuntime()
            let cwd = runtime.configLoaderForcedCwd()
            do {
                let udid = try resolveSimulator(runtime: runtime, cwd: cwd, provided: sim.simulator)
                _ = try runtime.simctl.terminateApp(simulatorUDID: udid, bundleId: bundleId, cwd: cwd)
            } catch {
                let e = mapError(error)
                if runtime.console.outputFormat == .json { try finishJSONError(e) }
                runtime.console.error(e.description)
                throw ExitCode(Int32(e.code.rawValue))
            }
        }
    }

    private static func resolveSimulator(runtime: SweetDeckRuntime, cwd: String, provided: String?) throws -> String {
        if let provided, !provided.isEmpty {
            if SweetDeckDestinationResolver.looksLikeUUID(provided) { return provided }
            // Try find by name:
            let devices = try runtime.simctl.listDevices(cwd: cwd)
            if let dev = devices.first(where: { $0.name == provided }) { return dev.udid }
            if let dev = devices.first(where: { $0.name.localizedCaseInsensitiveContains(provided) }) { return dev.udid }
            throw SweetDeckError(code: .simctlFailed, message: "Simulator not found", details: ["simulator": provided])
        }

        let loaded = try runtime.configLoader.load(from: cwd)
        let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: cwd, overrides: SweetDeckConfig())
        return try runtime.simctl.resolveUDID(destination: ctx.destination, cwd: cwd)
    }
}

struct Simulator: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage simulators via simctl.",
        subcommands: [List.self, Boot.self, Shutdown.self, Create.self, Delete.self, Prune.self, DeviceTypes.self, Runtimes.self, Location.self, Media.self]
    )
    func run() throws {}

    struct List: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Flag(help: "Print JSON (equivalent to simctl list -j devices).")
        var json: Bool = false
        func run() throws {
            let runtime = global.makeRuntime()
            do {
                if json {
                    _ = try runtime.process.runStreaming(SweetDeckCommand(executable: "/usr/bin/xcrun", arguments: ["simctl", "list", "-j"]), cwd: runtime.configLoaderForcedCwd(), streamToStdout: true, streamToStderr: true)
                } else {
                    let devices = try runtime.simctl.listDevices(cwd: runtime.configLoaderForcedCwd())
                    for d in devices.sorted(by: { $0.name < $1.name }) {
                        runtime.console.info("\(d.name) (\(d.udid)) \(d.state ?? "")")
                    }
                }
            } catch {
                let e = mapError(error)
                if runtime.console.outputFormat == .json { try finishJSONError(e) }
                runtime.console.error(e.description)
                throw ExitCode(Int32(e.code.rawValue))
            }
        }
    }

    struct Boot: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var simulator: String
        func run() throws {
            let runtime = global.makeRuntime()
            do { _ = try runtime.simctl.boot(simulator: simulator, cwd: runtime.configLoaderForcedCwd()) }
            catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
        }
    }

    struct Shutdown: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var simulator: String
        func run() throws {
            let runtime = global.makeRuntime()
            do {
                if simulator == "all" {
                    _ = try runtime.process.runStreaming(SweetDeckCommand(executable: "/usr/bin/xcrun", arguments: ["simctl", "shutdown", "all"]), cwd: runtime.configLoaderForcedCwd(), streamToStdout: true, streamToStderr: true)
                } else {
                    _ = try runtime.simctl.shutdown(simulator: simulator, cwd: runtime.configLoaderForcedCwd())
                }
            } catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
        }
    }

    struct Create: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var name: String
        @Option(name: .customLong("device-type")) var deviceType: String
        @Option(name: .customLong("runtime")) var runtimeID: String
        func run() throws {
            let runtime = global.makeRuntime()
            do { _ = try runtime.simctl.create(name: name, deviceType: deviceType, runtime: runtimeID, cwd: runtime.configLoaderForcedCwd()) }
            catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
        }
    }

    struct Delete: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Argument var simulator: String
        func run() throws {
            let runtime = global.makeRuntime()
            do { _ = try runtime.simctl.delete(simulator: simulator, cwd: runtime.configLoaderForcedCwd()) }
            catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
        }
    }

    struct Prune: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        func run() throws {
            let runtime = global.makeRuntime()
            do { _ = try runtime.simctl.deleteUnavailable(cwd: runtime.configLoaderForcedCwd()) }
            catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
        }
    }

    struct DeviceTypes: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        func run() throws {
            let runtime = global.makeRuntime()
            do { _ = try runtime.simctl.listDeviceTypes(cwd: runtime.configLoaderForcedCwd()) }
            catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
        }
    }

    struct Runtimes: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        func run() throws {
            let runtime = global.makeRuntime()
            do { _ = try runtime.simctl.listRuntimes(cwd: runtime.configLoaderForcedCwd()) }
            catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
        }
    }

    struct Location: ParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Set.self])
        func run() throws {}
        struct Set: ParsableCommand {
            @OptionGroup var global: GlobalOptions
            @Argument var simulator: String
            @Argument var lat: String
            @Argument var lon: String
            func run() throws {
                let runtime = global.makeRuntime()
                do { _ = try runtime.simctl.setLocation(simulator: simulator, latitude: lat, longitude: lon, cwd: runtime.configLoaderForcedCwd()) }
                catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
            }
        }
    }

    struct Media: ParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Add.self])
        func run() throws {}
        struct Add: ParsableCommand {
            @OptionGroup var global: GlobalOptions
            @Argument var simulator: String
            @Argument var paths: [String]
            func run() throws {
                let runtime = global.makeRuntime()
                do { _ = try runtime.simctl.addMedia(simulator: simulator, paths: paths.map { runtime.fs.absolutePath($0, relativeTo: runtime.configLoaderForcedCwd()) }, cwd: runtime.configLoaderForcedCwd()) }
                catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
            }
        }
    }
}

struct Device: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage physical devices via devicectl.",
        subcommands: [List.self, Install.self, Uninstall.self, Launch.self]
    )
    func run() throws {}

    struct List: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        func run() throws {
            let runtime = global.makeRuntime()
            do {
                let any = try runtime.devicectl.listDevices(cwd: runtime.configLoaderForcedCwd())
                if runtime.console.outputFormat == .json {
                    let data = try SweetDeckJSON.encodePretty(AnyEncodable(any))
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
                }
            } catch {
                let e = mapError(error)
                if runtime.console.outputFormat == .json { try finishJSONError(e) }
                runtime.console.error(e.description)
                throw ExitCode(Int32(e.code.rawValue))
            }
        }
    }

    struct Install: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Option(name: .customLong("device")) var device: String
        @Argument var path: String
        func run() throws {
            let runtime = global.makeRuntime()
            do {
                _ = try runtime.devicectl.installApp(device: device, appPath: runtime.fs.absolutePath(path, relativeTo: runtime.configLoaderForcedCwd()), cwd: runtime.configLoaderForcedCwd())
            } catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
        }
    }

    struct Uninstall: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Option(name: .customLong("device")) var device: String
        @Argument var bundleId: String
        func run() throws {
            let runtime = global.makeRuntime()
            do { _ = try runtime.devicectl.uninstallApp(device: device, bundleId: bundleId, cwd: runtime.configLoaderForcedCwd()) }
            catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
        }
    }

    struct Launch: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        @Option(name: .customLong("device")) var device: String
        @Argument var bundleId: String
        @Option(name: .customLong("app-arg"), parsing: .unconditionalSingleValue) var appArg: [String] = []
        @Option(name: .customLong("app-env"), parsing: .unconditionalSingleValue) var appEnv: [String] = []
        func run() throws {
            let runtime = global.makeRuntime()
            do {
                var env: [String: String] = [:]
                for kv in appEnv {
                    let parts = kv.split(separator: "=", maxSplits: 1).map(String.init)
                    if parts.count != 2 { throw ValidationError("--app-env must be KEY=VALUE") }
                    env[parts[0]] = parts[1]
                }
                let any = try runtime.devicectl.launchApp(device: device, bundleId: bundleId, args: appArg, env: env, cwd: runtime.configLoaderForcedCwd())
                if let pid = SweetDeckAnyJSONSearch.findFirstInt(any, keys: ["pid", "processIdentifier", "processID"]) {
                    runtime.state.recordDeviceLaunch(cwd: runtime.configLoaderForcedCwd(), state: SweetDeckDeviceLaunchState(device: device, bundleId: bundleId, pid: pid, timestamp: Date()))
                }
            } catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
        }
    }
}

struct Project: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Project editing tools (schemes/configs/packages).",
        subcommands: [List.self, Create.self, Packages.self]
    )
    func run() throws {}

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Schemes.self, Configs.self])
        func run() throws {}

        struct Schemes: ParsableCommand {
            @OptionGroup var global: GlobalOptions
            func run() throws {
                let runtime = global.makeRuntime()
                do {
                    let loaded = try runtime.configLoader.load(from: runtime.configLoaderForcedCwd())
                    let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: runtime.configLoaderForcedCwd(), overrides: SweetDeckConfig())
                    let schemes = try runtime.projectEdit.listSchemes(context: ctx, cwd: runtime.configLoaderForcedCwd())
                    if runtime.console.outputFormat == .json {
                        let data = try SweetDeckJSON.encodePretty(schemes)
                        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write("\n".data(using: .utf8)!)
                    } else {
                        schemes.forEach(runtime.console.info)
                    }
                } catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
            }
        }

        struct Configs: ParsableCommand {
            @OptionGroup var global: GlobalOptions
            func run() throws {
                let runtime = global.makeRuntime()
                do {
                    let loaded = try runtime.configLoader.load(from: runtime.configLoaderForcedCwd())
                    let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: runtime.configLoaderForcedCwd(), overrides: SweetDeckConfig())
                    let configs = try runtime.projectEdit.listConfigurations(context: ctx, cwd: runtime.configLoaderForcedCwd())
                    if runtime.console.outputFormat == .json {
                        let data = try SweetDeckJSON.encodePretty(configs)
                        FileHandle.standardOutput.write(data); FileHandle.standardOutput.write("\n".data(using: .utf8)!)
                    } else {
                        configs.forEach(runtime.console.info)
                    }
                } catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
            }
        }
    }

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [Config.self, Scheme.self])
        func run() throws {}

        struct Config: ParsableCommand {
            @OptionGroup var global: GlobalOptions
            @Argument var newName: String
            @Option(name: .customLong("based-on")) var basedOn: String
            @Option(help: "Scope: project|all-targets|target")
            var scope: String = "project"
            @Option(name: .customLong("target"), parsing: .unconditionalSingleValue)
            var target: [String] = []
            func run() throws {
                let runtime = global.makeRuntime()
                do {
                    let loaded = try runtime.configLoader.load(from: runtime.configLoaderForcedCwd())
                    let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: runtime.configLoaderForcedCwd(), overrides: SweetDeckConfig())
                    try runtime.projectEdit.createConfiguration(context: ctx, newName: newName, basedOn: basedOn, scope: scope, targets: target, cwd: runtime.configLoaderForcedCwd())
                    if runtime.console.outputFormat == .json { try finishJSONSuccess("Created configuration") }
                } catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
            }
        }

        struct Scheme: ParsableCommand {
            @OptionGroup var global: GlobalOptions
            @Argument var newName: String
            @Option(name: .customLong("based-on")) var basedOn: String
            @Option(help: "Build configuration name to set in the new scheme.")
            var configuration: String?
            @Flag(inversion: .prefixedNo, help: "Create under xcshareddata/xcschemes.")
            var shared: Bool = true
            func run() throws {
                let runtime = global.makeRuntime()
                do {
                    let loaded = try runtime.configLoader.load(from: runtime.configLoaderForcedCwd())
                    let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: runtime.configLoaderForcedCwd(), overrides: SweetDeckConfig())
                    try runtime.projectEdit.createScheme(context: ctx, newName: newName, basedOn: basedOn, configuration: configuration, shared: shared, cwd: runtime.configLoaderForcedCwd())
                    if runtime.console.outputFormat == .json { try finishJSONSuccess("Created scheme") }
                } catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
            }
        }
    }

    struct Packages: ParsableCommand {
        static let configuration = CommandConfiguration(subcommands: [List.self, Add.self, Remove.self, Link.self, Unlink.self])
        func run() throws {}

        struct List: ParsableCommand {
            @OptionGroup var global: GlobalOptions
            func run() throws {
                let runtime = global.makeRuntime()
                do {
                    let loaded = try runtime.configLoader.load(from: runtime.configLoaderForcedCwd())
                    let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: runtime.configLoaderForcedCwd(), overrides: SweetDeckConfig())
                    let any = try runtime.projectEdit.listPackages(context: ctx, cwd: runtime.configLoaderForcedCwd())
                    let data = try SweetDeckJSON.encodePretty(AnyEncodable(any))
                    FileHandle.standardOutput.write(data); FileHandle.standardOutput.write("\n".data(using: .utf8)!)
                } catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
            }
        }

        struct Add: ParsableCommand {
            @OptionGroup var global: GlobalOptions
            @Option(name: .customLong("url")) var url: String
            @Option(name: .customLong("from")) var from: String?
            @Option(name: .customLong("exact")) var exact: String?
            @Option(name: .customLong("branch")) var branch: String?
            @Option(name: .customLong("revision")) var revision: String?
            @Option(name: .customLong("link-product")) var linkProduct: String?
            @Option(name: .customLong("target"), parsing: .unconditionalSingleValue) var target: [String] = []
            func run() throws {
                let runtime = global.makeRuntime()
                do {
                    let requirement = try parseRequirement(from: from, exact: exact, branch: branch, revision: revision)
                    let loaded = try runtime.configLoader.load(from: runtime.configLoaderForcedCwd())
                    let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: runtime.configLoaderForcedCwd(), overrides: SweetDeckConfig())
                    try runtime.projectEdit.addPackage(context: ctx, url: url, requirement: requirement, linkProduct: linkProduct, targets: target, cwd: runtime.configLoaderForcedCwd())
                    if runtime.console.outputFormat == .json { try finishJSONSuccess("Added package") }
                } catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
            }

            private func parseRequirement(from: String?, exact: String?, branch: String?, revision: String?) throws -> SweetDeckPackageRequirement {
                let provided = [from != nil, exact != nil, branch != nil, revision != nil].filter { $0 }.count
                if provided != 1 { throw ValidationError("Specify exactly one of --from/--exact/--branch/--revision") }
                if let from { return .from(from) }
                if let exact { return .exact(exact) }
                if let branch { return .branch(branch) }
                return .revision(revision!)
            }
        }

        struct Remove: ParsableCommand {
            @OptionGroup var global: GlobalOptions
            @Option(name: .customLong("url")) var url: String?
            @Option(name: .customLong("identity")) var identity: String?
            func run() throws {
                let runtime = global.makeRuntime()
                do {
                    let loaded = try runtime.configLoader.load(from: runtime.configLoaderForcedCwd())
                    let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: runtime.configLoaderForcedCwd(), overrides: SweetDeckConfig())
                    try runtime.projectEdit.removePackage(context: ctx, url: url, identity: identity, cwd: runtime.configLoaderForcedCwd())
                    if runtime.console.outputFormat == .json { try finishJSONSuccess("Removed package") }
                } catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
            }
        }

        struct Link: ParsableCommand {
            @OptionGroup var global: GlobalOptions
            @Option(name: .customLong("product")) var product: String
            @Option(name: .customLong("target")) var target: String
            func run() throws {
                let runtime = global.makeRuntime()
                do {
                    let loaded = try runtime.configLoader.load(from: runtime.configLoaderForcedCwd())
                    let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: runtime.configLoaderForcedCwd(), overrides: SweetDeckConfig())
                    try runtime.projectEdit.linkProduct(context: ctx, product: product, target: target, cwd: runtime.configLoaderForcedCwd())
                    if runtime.console.outputFormat == .json { try finishJSONSuccess("Linked product") }
                } catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
            }
        }

        struct Unlink: ParsableCommand {
            @OptionGroup var global: GlobalOptions
            @Option(name: .customLong("product")) var product: String
            @Option(name: .customLong("target")) var target: String
            func run() throws {
                let runtime = global.makeRuntime()
                do {
                    let loaded = try runtime.configLoader.load(from: runtime.configLoaderForcedCwd())
                    let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: runtime.configLoaderForcedCwd(), overrides: SweetDeckConfig())
                    try runtime.projectEdit.unlinkProduct(context: ctx, product: product, target: target, cwd: runtime.configLoaderForcedCwd())
                    if runtime.console.outputFormat == .json { try finishJSONSuccess("Unlinked product") }
                } catch { let e = mapError(error); if runtime.console.outputFormat == .json { try finishJSONError(e) }; runtime.console.error(e.description); throw ExitCode(Int32(e.code.rawValue)) }
            }
        }
    }
}

struct License: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Xcode license/first-launch helpers.",
        subcommands: [Status.self, Accept.self]
    )
    func run() throws { try Status().run() }

    struct Status: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        func run() throws {
            let runtime = global.makeRuntime()
            do {
                _ = try runtime.process.runStreaming(SweetDeckCommand(executable: "/usr/bin/xcodebuild", arguments: ["-version"]), cwd: runtime.configLoaderForcedCwd(), streamToStdout: true, streamToStderr: true)
                let res = try runtime.process.runCapture(SweetDeckCommand(executable: "/usr/bin/xcodebuild", arguments: ["-checkFirstLaunchStatus"]), cwd: runtime.configLoaderForcedCwd())
                if runtime.console.outputFormat == .json {
                    struct Details: Encodable { var exit: Int32; var stdout: String; var stderr: String }
                    try finishJSONSuccess("OK", details: Details(exit: res.exitCode, stdout: String(data: res.stdout, encoding: .utf8) ?? "", stderr: String(data: res.stderr, encoding: .utf8) ?? ""))
                } else {
                    runtime.console.info("xcodebuild -checkFirstLaunchStatus exit=\(res.exitCode)")
                }
            } catch {
                let e = mapError(error)
                if runtime.console.outputFormat == .json { try finishJSONError(e) }
                runtime.console.error(e.description)
                throw ExitCode(Int32(e.code.rawValue))
            }
        }
    }

    struct Accept: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        func run() throws {
            let runtime = global.makeRuntime()
            do {
                _ = try runtime.process.runStreaming(SweetDeckCommand(executable: "/usr/bin/xcodebuild", arguments: ["-runFirstLaunch"]), cwd: runtime.configLoaderForcedCwd(), streamToStdout: true, streamToStderr: true)
            } catch {
                let e = mapError(error)
                if runtime.console.outputFormat == .json { try finishJSONError(e) }
                runtime.console.error(e.description)
                throw ExitCode(Int32(e.code.rawValue))
            }
        }
    }
}

struct Update: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Update helpers (Homebrew-based).",
        subcommands: [Check.self, SelfUpdate.self]
    )
    func run() throws { try Check().run() }

    struct Check: ParsableCommand {
        @OptionGroup var global: GlobalOptions
        func run() throws {
            let runtime = global.makeRuntime()
            // Best-effort: network may be blocked.
            let url = "https://api.github.com/repos/REPLACE_OWNER/REPLACE_REPO/releases/latest"
            do {
                let res = try runtime.process.runCapture(SweetDeckCommand(executable: "/usr/bin/curl", arguments: ["-fsSL", url]), cwd: runtime.configLoaderForcedCwd())
                if res.exitCode != 0 {
                    runtime.console.warn("Offline or repo not configured. Update URL in Sources/SweetDeckCLI/Commands.swift.")
                    if runtime.console.outputFormat == .json { try finishJSONSuccess("Offline", details: ["current": SweetDeckVersion.current]) }
                    return
                }
                let any = try SweetDeckJSON.parseAny(from: res.stdout)
                let tag = (any as? [String: Any])?["tag_name"] as? String
                if runtime.console.outputFormat == .json {
                    try finishJSONSuccess("OK", details: ["current": SweetDeckVersion.current, "latest": tag ?? "unknown"])
                } else {
                    runtime.console.info("Current: \(SweetDeckVersion.current)")
                    runtime.console.info("Latest: \(tag ?? "unknown")")
                }
            } catch {
                runtime.console.warn("Update check failed: \(error)")
                if runtime.console.outputFormat == .json { try finishJSONSuccess("Offline", details: ["current": SweetDeckVersion.current]) }
            }
        }
    }

    struct SelfUpdate: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "self", abstract: "Attempt to upgrade via Homebrew.")
        @OptionGroup var global: GlobalOptions
        func run() throws {
            let runtime = global.makeRuntime()
            do {
                _ = try runtime.process.runStreaming(SweetDeckCommand(executable: "/usr/bin/env", arguments: ["brew", "upgrade", "sweetdeck"]), cwd: runtime.configLoaderForcedCwd(), streamToStdout: true, streamToStderr: true)
            } catch {
                runtime.console.error("Homebrew upgrade failed. If installed via brew, try: brew upgrade sweetdeck")
                let e = mapError(error)
                if runtime.console.outputFormat == .json { try finishJSONError(e) }
                throw ExitCode(Int32(e.code.rawValue))
            }
        }
    }
}

// MARK: - Helpers

private func schemeOverrides(runtime: SweetDeckRuntime, usecases: SweetDeckUseCases, global: GlobalOptions) throws -> SweetDeckConfig {
    let overrideScheme = try usecases.resolveSchemeOverride(
        cwd: runtime.configLoaderForcedCwd(),
        overrideScheme: global.scheme,
        pickScheme: global.pickScheme,
        nonInteractive: false
    )
    return SweetDeckConfig(scheme: overrideScheme)
}

extension SweetDeckRuntime {
    func configLoaderForcedCwd() -> String {
        self.cwd
    }
}

/// Minimal type-erased Encodable wrapper for JSON output.
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encodeFunc = value.encode
    }

    init(_ value: Any) {
        self.encodeFunc = { encoder in
            var container = encoder.singleValueContainer()
            if let dict = value as? [String: Any] {
                try container.encode(dict.mapValues(AnyEncodable.init))
            } else if let arr = value as? [Any] {
                try container.encode(arr.map(AnyEncodable.init))
            } else if let s = value as? String {
                try container.encode(s)
            } else if let i = value as? Int {
                try container.encode(i)
            } else if let b = value as? Bool {
                try container.encode(b)
            } else if value is NSNull {
                try container.encodeNil()
            } else {
                try container.encode(String(describing: value))
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}
