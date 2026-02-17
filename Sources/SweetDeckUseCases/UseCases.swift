import Foundation
import SweetDeckDomain
import SweetDeckInfra
import SweetDeckXcode

public struct SweetDeckInitOptions: Sendable {
    public var projectPath: String?
    public var projectType: SweetDeckProjectType?
    public var scheme: String?
    public var schemes: [String]
    public var pickScheme: Bool
    public var configuration: String
    public var destination: String?
    public var derivedDataPath: String?
    public var xcodebuildArgs: [String]
    public var bundleId: String?
    public var appArgs: [String]
    public var appEnv: [String: String]

    public init(
        projectPath: String?,
        projectType: SweetDeckProjectType?,
        scheme: String?,
        schemes: [String],
        pickScheme: Bool,
        configuration: String,
        destination: String?,
        derivedDataPath: String?,
        xcodebuildArgs: [String],
        bundleId: String?,
        appArgs: [String],
        appEnv: [String: String]
    ) {
        self.projectPath = projectPath
        self.projectType = projectType
        self.scheme = scheme
        self.schemes = schemes
        self.pickScheme = pickScheme
        self.configuration = configuration
        self.destination = destination
        self.derivedDataPath = derivedDataPath
        self.xcodebuildArgs = xcodebuildArgs
        self.bundleId = bundleId
        self.appArgs = appArgs
        self.appEnv = appEnv
    }
}

public final class SweetDeckUseCases: @unchecked Sendable {
    private let runtime: SweetDeckRuntime

    public init(runtime: SweetDeckRuntime) {
        self.runtime = runtime
    }

    public func initProject(cwd: String, options: SweetDeckInitOptions) throws -> SweetDeckResolvedContext {
        let fs = runtime.fs
        let console = runtime.console

        let projectPath = try resolveProjectPath(cwd: cwd, provided: options.projectPath)
        let projectType = options.projectType ?? inferProjectType(from: projectPath)

        let projectRef = SweetDeckProjectRef(path: projectPath, type: projectType)
        let listing = try runtime.xcodebuild.list(project: projectRef, cwd: cwd)
        let discoveredSchemes = listing.schemes

        let overrideScheme = options.scheme?.trimmingCharacters(in: .whitespacesAndNewlines)
        var schemesList = options.schemes
        if schemesList.isEmpty {
            if !discoveredSchemes.isEmpty {
                schemesList = discoveredSchemes
            } else if let overrideScheme {
                schemesList = [overrideScheme]
            }
        }

        if options.pickScheme {
            console.warn("--pick-scheme is interactive and has been removed; using resolved/default scheme.")
        }

        if schemesList.isEmpty {
            throw SweetDeckError(code: .config, message: "Could not determine scheme list. Use --schemes or ensure xcodebuild -list works.")
        }

        if !discoveredSchemes.isEmpty {
            let unknown = schemesList.filter { !discoveredSchemes.contains($0) }
            if !unknown.isEmpty {
                console.warn("Some schemes are not in xcodebuild -list: \(unknown.joined(separator: ", "))")
            }
        }

        let defaultScheme: String
        if let overrideScheme, !overrideScheme.isEmpty {
            defaultScheme = overrideScheme
        } else {
            defaultScheme = schemesList.first!
        }

        let destination: String
        if let provided = options.destination?.trimmingCharacters(in: .whitespacesAndNewlines), !provided.isEmpty {
            destination = provided
        } else {
            destination = try preferredSimulatorDestination(cwd: cwd)
        }

        if !schemesList.contains(defaultScheme) {
            console.warn("Default scheme '\(defaultScheme)' not in schemes list; adding it.")
            schemesList.append(defaultScheme)
        }

        let resolvedDerivedData = options.derivedDataPath
            ?? runtime.configLoader.derivedDataPathFromSettings(project: projectRef, cwd: cwd)
            ?? ".sweetdeck/DerivedData"

        let config = SweetDeckConfig(
            project: projectRef,
            scheme: defaultScheme,
            schemes: schemesList,
            defaultScheme: defaultScheme,
            configuration: options.configuration,
            destination: destination,
            derivedDataPath: resolvedDerivedData,
            xcodebuildArguments: options.xcodebuildArgs,
            appLaunch: SweetDeckAppLaunch(bundleIdentifier: options.bundleId, arguments: options.appArgs, environment: options.appEnv)
        )

        let baseDir = fs.absolutePath(".sweetdeck", relativeTo: cwd)
        try fs.createDirectory(at: baseDir)
        let configPath = fs.absolutePath(".sweetdeck/config.json", relativeTo: cwd)
        let data = try SweetDeckJSON.encodePretty(config)
        try fs.writeAtomic(data: data, to: configPath)
        console.info("Wrote \(configPath)")

        let loaded = SweetDeckLoadedConfig(configPath: configPath, loadedFrom: ".sweetdeck/config.json", config: config)
        return try runtime.configLoader.resolveContext(loaded: loaded, cwd: cwd, overrides: SweetDeckConfig())
    }

    public func resolveSchemeOverride(
        cwd: String,
        overrideScheme: String?,
        pickScheme: Bool,
        nonInteractive: Bool
    ) throws -> String? {
        if let overrideScheme, !overrideScheme.isEmpty { return overrideScheme }
        guard pickScheme else { return nil }
        _ = nonInteractive
        throw SweetDeckError(code: .usage, message: "--pick-scheme requires interactive mode, which is no longer supported. Pass --scheme <name> instead.")
    }

    public func context(cwd: String, refresh: Bool, overrides: SweetDeckConfig) throws -> (SweetDeckResolvedContext, [String]?, Any?) {
        let loaded = try runtime.configLoader.load(from: cwd)
        let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: cwd, overrides: overrides)
        if !refresh { return (ctx, nil, nil) }
        let listing = try runtime.xcodebuild.list(project: ctx.project, cwd: cwd)
        let devicesAny: Any?
        do {
            let devices = try runtime.simctl.listDevices(cwd: cwd)
            devicesAny = devices
        } catch {
            runtime.console.warn("Failed to refresh simulator list: \(error)")
            devicesAny = nil
        }
        return (ctx, listing.schemes, devicesAny)
    }

    public func build(cwd: String, overrides: SweetDeckConfig, cleanFirst: Bool, extraArgs: [String]) throws -> SweetDeckRunResult {
        let loaded = try runtime.configLoader.load(from: cwd)
        let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: cwd, overrides: overrides)
        if cleanFirst {
            _ = try withSpinner(message: "Cleaning") {
                try runtime.xcodebuild.clean(context: ctx, extraArgs: extraArgs, stream: runtime.console.verbose, cwd: cwd)
            }
        }
        return try withSpinner(message: "Building") {
            try runtime.xcodebuild.build(context: ctx, extraArgs: extraArgs, stream: runtime.console.verbose, cwd: cwd)
        }
    }

    public func clean(cwd: String, overrides: SweetDeckConfig, deleteDerivedData: Bool, extraArgs: [String]) throws {
        let loaded = try runtime.configLoader.load(from: cwd)
        let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: cwd, overrides: overrides)
        _ = try withSpinner(message: "Cleaning") {
            try runtime.xcodebuild.clean(context: ctx, extraArgs: extraArgs, stream: runtime.console.verbose, cwd: cwd)
        }
        if deleteDerivedData, runtime.fs.directoryExists(at: ctx.derivedDataPath) {
            try runtime.fs.removeItem(at: ctx.derivedDataPath)
            runtime.console.info("Deleted \(ctx.derivedDataPath)")
        }
    }

    public func test(
        cwd: String,
        overrides: SweetDeckConfig,
        cleanFirst: Bool,
        only: [String],
        skip: [String],
        resultBundlePath: String?,
        extraArgs: [String]
    ) throws -> SweetDeckRunResult {
        let loaded = try runtime.configLoader.load(from: cwd)
        let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: cwd, overrides: overrides)

        var args = extraArgs
        for o in only { args.append("-only-testing:\(o)") }
        for s in skip { args.append("-skip-testing:\(s)") }
        if let resultBundlePath { args += ["-resultBundlePath", runtime.fs.absolutePath(resultBundlePath, relativeTo: cwd)] }

        if cleanFirst {
            _ = try withSpinner(message: "Cleaning") {
                try runtime.xcodebuild.clean(context: ctx, extraArgs: [], stream: runtime.console.verbose, cwd: cwd)
            }
        }
        return try withSpinner(message: "Testing") {
            try runtime.xcodebuild.test(context: ctx, extraArgs: args, stream: runtime.console.verbose, cwd: cwd)
        }
    }

    public func discoverTests(cwd: String, root: String) -> [SweetDeckDiscoveredTest] {
        SweetDeckTestDiscovery.discover(fs: runtime.fs, root: runtime.fs.absolutePath(root, relativeTo: cwd))
    }

    public func run(
        cwd: String,
        overrides: SweetDeckConfig,
        noBuild: Bool,
        reinstall: Bool,
        device: String?,
        bundleIdOverride: String?,
        appArgsOverride: [String],
        appEnvOverride: [String: String],
        extraXcodeArgs: [String]
    ) throws -> (SweetDeckBuildAppPath, Any?) {
        let loaded = try runtime.configLoader.load(from: cwd)
        var ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: cwd, overrides: overrides)

        if let bundleIdOverride {
            var app = ctx.appLaunch
            app.bundleIdentifier = bundleIdOverride
            ctx.appLaunch = app
        }
        if !appArgsOverride.isEmpty {
            var app = ctx.appLaunch
            app.arguments = appArgsOverride
            ctx.appLaunch = app
        }
        if !appEnvOverride.isEmpty {
            var app = ctx.appLaunch
            for (k, v) in appEnvOverride { app.environment[k] = v }
            ctx.appLaunch = app
        }

        var buildCtx = ctx
        let simulatorOverrideUDID = try device.flatMap { try resolveSimulatorUDID(cwd: cwd, provided: $0) }
        if let device, !device.isEmpty {
            if let simUDID = simulatorOverrideUDID {
                buildCtx.destination = "id=\(simUDID)"
            } else if SweetDeckDestinationResolver.looksLikeUUID(device) {
                buildCtx.destination = "id=\(device)"
            } else {
                buildCtx.destination = "name=\(device)"
            }
        }

        if !noBuild {
            _ = try withSpinner(message: "Building") {
                try runtime.xcodebuild.build(context: buildCtx, extraArgs: extraXcodeArgs, stream: runtime.console.verbose, cwd: cwd)
            }
        }

        let any = try runtime.xcodebuild.showBuildSettingsJSON(context: buildCtx, extraArgs: extraXcodeArgs, cwd: cwd)
        guard let buildSettings = SweetDeckAnyJSONSearch.findFirstDictionary(any, whereKeysExist: ["TARGET_BUILD_DIR", "FULL_PRODUCT_NAME"]),
              let targetBuildDir = buildSettings["TARGET_BUILD_DIR"] as? String,
              let fullProductName = buildSettings["FULL_PRODUCT_NAME"] as? String
        else {
            throw SweetDeckError(code: .xcodebuildFailed, message: "Could not determine built .app path from build settings")
        }
        let appPath = URL(fileURLWithPath: targetBuildDir).appendingPathComponent(fullProductName).path

        let bundleId = ctx.appLaunch.bundleIdentifier ?? readBundleIdentifier(appPath: appPath)
        guard let bundleId, !bundleId.isEmpty else {
            throw SweetDeckError(code: .config, message: "Missing bundle identifier. Set appLaunch.bundleIdentifier in config or pass --bundle-id.")
        }

        if let simUDID = simulatorOverrideUDID {
            try ensureSimulatorBooted(cwd: cwd, udid: simUDID)
            if reinstall {
                runtime.console.info("Installing on simulator \(formatSimulatorName(cwd: cwd, udid: simUDID))")
                _ = try runtime.simctl.installApp(simulatorUDID: simUDID, appPath: appPath, cwd: cwd)
            }
            runtime.console.info("Launching on simulator \(formatSimulatorName(cwd: cwd, udid: simUDID))")
            _ = try runtime.simctl.launchApp(simulatorUDID: simUDID, bundleId: bundleId, args: ctx.appLaunch.arguments, env: ctx.appLaunch.environment, cwd: cwd)
            runtime.state.recordSimulatorLaunch(cwd: cwd, state: SweetDeckSimulatorLaunchState(simulatorUDID: simUDID, bundleId: bundleId, timestamp: Date()))
            return (SweetDeckBuildAppPath(appPath: appPath, bundleIdentifier: bundleId), ["simulatorUDID": simUDID])
        } else if let device {
            let resolvedDevice = try resolveDeviceIdentifier(cwd: cwd, provided: device)
            var details: Any?
            if reinstall {
                runtime.console.info("Installing on device \(resolvedDevice)")
                details = try runtime.devicectl.installApp(device: resolvedDevice, appPath: appPath, cwd: cwd)
            }
            runtime.console.info("Launching on device \(resolvedDevice)")
            let launchAny = try runtime.devicectl.launchApp(device: resolvedDevice, bundleId: bundleId, args: ctx.appLaunch.arguments, env: ctx.appLaunch.environment, cwd: cwd)
            if let pid = SweetDeckAnyJSONSearch.findFirstInt(launchAny, keys: ["pid", "processIdentifier", "processID"]) {
                runtime.state.recordDeviceLaunch(cwd: cwd, state: SweetDeckDeviceLaunchState(device: resolvedDevice, bundleId: bundleId, pid: pid, timestamp: Date()))
            }
            return (SweetDeckBuildAppPath(appPath: appPath, bundleIdentifier: bundleId), ["install": details as Any, "launch": launchAny as Any])
        } else {
            let udid = try runtime.simctl.resolveUDID(destination: ctx.destination, cwd: cwd)
            try ensureSimulatorBooted(cwd: cwd, udid: udid)
            if reinstall {
                runtime.console.info("Installing on simulator \(formatSimulatorName(cwd: cwd, udid: udid))")
                _ = try runtime.simctl.installApp(simulatorUDID: udid, appPath: appPath, cwd: cwd)
            }
            runtime.console.info("Launching on simulator \(formatSimulatorName(cwd: cwd, udid: udid))")
            _ = try runtime.simctl.launchApp(simulatorUDID: udid, bundleId: bundleId, args: ctx.appLaunch.arguments, env: ctx.appLaunch.environment, cwd: cwd)
            runtime.state.recordSimulatorLaunch(cwd: cwd, state: SweetDeckSimulatorLaunchState(simulatorUDID: udid, bundleId: bundleId, timestamp: Date()))
            return (SweetDeckBuildAppPath(appPath: appPath, bundleIdentifier: bundleId), ["simulatorUDID": udid])
        }
    }

    private func withSpinner<T>(message: String, work: () throws -> T) throws -> T {
        guard runtime.console.shouldSpin else { return try work() }
        let spinner = SweetDeckSpinner(message: message)
        spinner.start()
        do {
            let result = try work()
            spinner.stop(finalMessage: message)
            return result
        } catch {
            spinner.stop(finalMessage: "\(message) failed")
            throw error
        }
    }

    public func logs(
        cwd: String,
        overrides: SweetDeckConfig,
        bundleIdOverride: String?,
        style: String,
        level: String,
        search: String?
    ) throws {
        let loaded = try runtime.configLoader.load(from: cwd)
        let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: cwd, overrides: overrides)
        var bundleId = bundleIdOverride ?? ctx.appLaunch.bundleIdentifier
        if bundleId?.isEmpty != false {
            bundleId = try resolveBundleIdFromBuildSettings(context: ctx, cwd: cwd)
        }
        guard let bundleId, !bundleId.isEmpty else {
            throw SweetDeckError(code: .config, message: "Missing bundle identifier. Set appLaunch.bundleIdentifier in config, pass --bundle-id, or ensure PRODUCT_BUNDLE_IDENTIFIER is available.")
        }
        let udid = try runtime.simctl.resolveUDID(destination: ctx.destination, cwd: cwd)
        let appName = bundleId.split(separator: ".").last.map(String.init) ?? bundleId
        let bundlePredicate = "("
            + "process == \"\(appName)\""
            + " OR processImagePath CONTAINS[c] \"\(appName).app\""
            + " OR senderImagePath CONTAINS[c] \"\(appName).app\""
            + " OR subsystem == \"\(bundleId)\""
            + " OR subsystem BEGINSWITH \"\(bundleId).\""
            + ")"
        let searchPredicate = search.map { #"eventMessage CONTAINS[c] "\#($0.replacingOccurrences(of: "\"", with: "\\\""))""# }
        let predicate = searchPredicate.map { "\(bundlePredicate) AND (\($0))" } ?? bundlePredicate
        _ = try runtime.simctl.logStream(simulatorUDID: udid, style: style, level: level, predicate: predicate, cwd: cwd)
    }

    public func stop(cwd: String, overrides: SweetDeckConfig, device: String?, bundleIdOverride: String?, pid: Int?, kill: Bool) throws {
        let loaded = try runtime.configLoader.load(from: cwd)
        let ctx = try runtime.configLoader.resolveContext(loaded: loaded, cwd: cwd, overrides: overrides)
        var bundleId = bundleIdOverride ?? ctx.appLaunch.bundleIdentifier

        if let device {
            guard let bundleId, !bundleId.isEmpty else {
                throw SweetDeckError(code: .config, message: "Missing bundle identifier. Set appLaunch.bundleIdentifier in config or pass --bundle-id.")
            }
            let resolvedDevice = try resolveDeviceIdentifier(cwd: cwd, provided: device)
            let effectivePID = pid ?? runtime.state.findPID(cwd: cwd, device: resolvedDevice, bundleId: bundleId)
            guard let effectivePID else {
                throw SweetDeckError(code: .devicectlFailed, message: "Device stop requires --pid (or a prior `sweetdeck run --device ...`)", details: ["bundleId": bundleId, "device": resolvedDevice])
            }
            _ = try runtime.devicectl.terminate(device: resolvedDevice, pid: effectivePID, kill: kill, cwd: cwd)
        } else {
            if bundleId?.isEmpty != false {
                bundleId = try resolveBundleIdFromBuildSettings(context: ctx, cwd: cwd)
            }
            if let bundleId, let lastDevice = runtime.state.findLastDeviceLaunch(cwd: cwd, bundleId: bundleId) {
                _ = try runtime.devicectl.terminate(device: lastDevice.device, pid: lastDevice.pid, kill: kill, cwd: cwd)
                return
            }
            let udid = try runtime.simctl.resolveUDID(destination: ctx.destination, cwd: cwd)
            if bundleId?.isEmpty != false {
                bundleId = runtime.state.findLastSimulatorBundleId(cwd: cwd, simulatorUDID: udid)
            }
            guard let bundleId, !bundleId.isEmpty else {
                throw SweetDeckError(code: .config, message: "Missing bundle identifier. Set appLaunch.bundleIdentifier in config, pass --bundle-id, or run `sweetdeck run` first.")
            }
            _ = try runtime.simctl.terminateApp(simulatorUDID: udid, bundleId: bundleId, cwd: cwd)
        }
    }

    private func resolveProjectPath(cwd: String, provided: String?) throws -> String {
        let fs = runtime.fs
        if let provided {
            let abs = fs.absolutePath(provided, relativeTo: cwd)
            guard fs.directoryExists(at: abs) || fs.fileExists(at: abs) else {
                throw SweetDeckError(code: .config, message: "Project path does not exist", details: ["path": abs])
            }
            return abs
        }

        let candidates = (try? fs.listDirectory(at: cwd)) ?? []
        if let ws = candidates.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return fs.absolutePath(ws, relativeTo: cwd)
        }
        if let proj = candidates.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return fs.absolutePath(proj, relativeTo: cwd)
        }

        throw SweetDeckError(code: .config, message: "Could not auto-detect .xcworkspace or .xcodeproj in \(cwd). Use --project-path.")
    }

    private func inferProjectType(from path: String) -> SweetDeckProjectType {
        if path.hasSuffix(".xcworkspace") { return .xcworkspace }
        return .xcodeproj
    }

    private func readBundleIdentifier(appPath: String) -> String? {
        let infoPlist = URL(fileURLWithPath: appPath).appendingPathComponent("Info.plist").path
        guard FileManager.default.fileExists(atPath: infoPlist),
              let data = try? Data(contentsOf: URL(fileURLWithPath: infoPlist)),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any]
        else { return nil }
        return dict["CFBundleIdentifier"] as? String
    }

    private func preferredSimulatorDestination(cwd: String) throws -> String {
        let console = runtime.console
        let fallback = "platform=iOS Simulator,name=iPhone"
        let devices: [SweetDeckSimulatorDevice]
        do {
            devices = try runtime.simctl.listDevices(cwd: cwd)
        } catch {
            console.warn("Failed to list simulators; using default destination.")
            return fallback
        }

        let available = devices.filter { $0.isAvailable != false }
        guard !available.isEmpty else {
            console.warn("No available simulators found; using default destination.")
            return fallback
        }

        let sorted = available.sorted {
            if $0.name == $1.name { return ($0.runtime ?? "") > ($1.runtime ?? "") }
            return $0.name < $1.name
        }

        let preferred =
            sorted.first(where: { $0.state?.caseInsensitiveCompare("Booted") == .orderedSame && $0.name.localizedCaseInsensitiveContains("iPhone") })
            ?? sorted.first(where: { $0.state?.caseInsensitiveCompare("Booted") == .orderedSame })
            ?? sorted.first(where: { $0.name.localizedCaseInsensitiveContains("iPhone") })
            ?? sorted.first

        guard let preferred else { return fallback }
        return "platform=iOS Simulator,id=\(preferred.udid)"
    }

    private func ensureSimulatorBooted(cwd: String, udid: String) throws {
        let devices = try runtime.simctl.listDevices(cwd: cwd)
        guard let device = devices.first(where: { $0.udid == udid }) else { return }
        if device.state?.caseInsensitiveCompare("Booted") == .orderedSame { return }
        _ = try runtime.simctl.boot(simulator: udid, cwd: cwd)
    }

    private func formatSimulatorName(cwd: String, udid: String) -> String {
        if let device = try? runtime.simctl.listDevices(cwd: cwd).first(where: { $0.udid == udid }) {
            let runtimeName = device.runtime ?? "Unknown Runtime"
            return "\(device.name) (\(runtimeName)) [\(udid)]"
        }
        return udid
    }

    private func resolveSimulatorUDID(cwd: String, provided: String) throws -> String? {
        let trimmed = provided.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let devices = try runtime.simctl.listDevices(cwd: cwd)
        if let exact = devices.first(where: { $0.udid == trimmed }) { return exact.udid }
        if let exact = devices.first(where: { $0.name == trimmed }) { return exact.udid }
        if let match = devices.first(where: { $0.name.localizedCaseInsensitiveContains(trimmed) }) { return match.udid }
        if let match = devices.first(where: { $0.udid.localizedCaseInsensitiveContains(trimmed) }) { return match.udid }
        return nil
    }

    private func resolveDeviceIdentifier(cwd: String, provided: String) throws -> String {
        let trimmed = provided.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return provided }

        let any = try runtime.devicectl.listDevices(cwd: cwd)
        let candidates = extractDeviceCandidates(from: any)
        if let matched = matchDevice(candidates: candidates, provided: trimmed) {
            return matched
        }
        return trimmed
    }

    private func extractDeviceCandidates(from any: Any) -> [[String: Any]] {
        var out: [[String: Any]] = []
        if let dict = any as? [String: Any] {
            if dict["name"] != nil || dict["identifier"] != nil || dict["udid"] != nil || dict["deviceIdentifier"] != nil || dict["id"] != nil {
                out.append(dict)
            }
            for (_, v) in dict {
                out.append(contentsOf: extractDeviceCandidates(from: v))
            }
        } else if let arr = any as? [Any] {
            for v in arr { out.append(contentsOf: extractDeviceCandidates(from: v)) }
        }
        return out
    }

    private func matchDevice(candidates: [[String: Any]], provided: String) -> String? {
        func field(_ dict: [String: Any], _ key: String) -> String? {
            dict[key] as? String
        }
        let keys = ["identifier", "udid", "deviceIdentifier", "id", "name"]
        for dict in candidates {
            for key in keys {
                if let val = field(dict, key), val == provided {
                    return field(dict, "identifier") ?? field(dict, "udid") ?? val
                }
            }
        }
        for dict in candidates {
            for key in keys {
                if let val = field(dict, key), val.localizedCaseInsensitiveContains(provided) {
                    return field(dict, "identifier") ?? field(dict, "udid") ?? val
                }
            }
        }
        return nil
    }

    private func resolveBundleIdFromBuildSettings(context: SweetDeckResolvedContext, cwd: String) throws -> String? {
        let any = try runtime.xcodebuild.showBuildSettingsJSON(context: context, extraArgs: [], cwd: cwd)
        if let settings = SweetDeckAnyJSONSearch.findFirstDictionary(any, whereKeysExist: ["PRODUCT_BUNDLE_IDENTIFIER"]),
           let bundleId = settings["PRODUCT_BUNDLE_IDENTIFIER"] as? String,
           !bundleId.isEmpty {
            return bundleId
        }
        return nil
    }
}
