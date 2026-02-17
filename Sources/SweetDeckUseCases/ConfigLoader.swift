import Foundation
import SweetDeckDomain
import SweetDeckInfra

public struct SweetDeckLoadedConfig: Sendable {
    public var configPath: String?
    public var loadedFrom: String?
    public var config: SweetDeckConfig
}

public final class SweetDeckConfigLoader: @unchecked Sendable {
    private let fs: SweetDeckFileSysteming
    private let console: SweetDeckConsole
    private let forcedConfigPath: String?

    public init(fs: SweetDeckFileSysteming, console: SweetDeckConsole, forcedConfigPath: String?) {
        self.fs = fs
        self.console = console
        self.forcedConfigPath = forcedConfigPath
    }

    public func load(from cwd: String) throws -> SweetDeckLoadedConfig {
        if let forcedConfigPath {
            guard fs.fileExists(at: forcedConfigPath) else {
                throw SweetDeckError(code: .config, message: "Config not found", details: ["path": forcedConfigPath])
            }
            return SweetDeckLoadedConfig(configPath: forcedConfigPath, loadedFrom: forcedConfigPath, config: try readConfig(at: forcedConfigPath))
        }

        let sweet = ".sweetdeck/config.json"
        let flow = ".flowdeck/config.json"
        let found = fs.findUpward(from: cwd, candidates: [sweet, flow])
        guard let found else {
            throw SweetDeckError(code: .config, message: "No config found. Run `sweetdeck init` first.")
        }

        let baseDir = URL(fileURLWithPath: found.foundPath).deletingLastPathComponent().path
        let sweetPath = fs.absolutePath(sweet, relativeTo: baseDir)
        let flowPath = fs.absolutePath(flow, relativeTo: baseDir)
        let alsoSweet = fs.fileExists(at: sweetPath)
        let alsoFlow = fs.fileExists(at: flowPath)
        if alsoSweet, alsoFlow, found.matchedName == flow {
            console.warn("Both .sweetdeck/config.json and .flowdeck/config.json exist; using .sweetdeck/config.json")
            return SweetDeckLoadedConfig(configPath: sweetPath, loadedFrom: sweet, config: try readConfig(at: sweetPath))
        }

        return SweetDeckLoadedConfig(configPath: found.foundPath, loadedFrom: found.matchedName, config: try readConfig(at: found.foundPath))
    }

    public func resolveContext(
        loaded: SweetDeckLoadedConfig,
        cwd: String,
        overrides: SweetDeckConfig
    ) throws -> SweetDeckResolvedContext {
        let merged = merge(base: loaded.config, override: overrides)
        guard let project = merged.project else {
            throw SweetDeckError(code: .config, message: "Missing project in config")
        }
        let schemesList = (merged.schemes ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let scheme = (overrides.scheme?.isEmpty == false ? overrides.scheme : nil)
            ?? (merged.defaultScheme?.isEmpty == false ? merged.defaultScheme : nil)
            ?? (merged.scheme?.isEmpty == false ? merged.scheme : nil)
            ?? schemesList.first
        guard let scheme, !scheme.isEmpty else {
            throw SweetDeckError(code: .config, message: "Missing scheme in config")
        }
        if !schemesList.isEmpty, !schemesList.contains(scheme) {
            console.warn("Selected scheme '\(scheme)' is not in config.schemes; proceeding anyway.")
        }

        let configuration = merged.configuration?.isEmpty == false ? merged.configuration! : "Debug"
        let destination = merged.destination?.isEmpty == false ? merged.destination! : "platform=iOS Simulator,name=iPhone"
        let derivedDataPath = merged.derivedDataPath?.isEmpty == false
            ? merged.derivedDataPath!
            : (derivedDataPathFromSettings(project: project, cwd: cwd) ?? ".sweetdeck/DerivedData")
        let xcodeArgs = merged.xcodebuildArguments ?? []
        let appLaunch = merged.appLaunch ?? SweetDeckAppLaunch()

        return SweetDeckResolvedContext(
            configPath: loaded.configPath,
            loadedFrom: loaded.loadedFrom,
            project: project,
            scheme: scheme,
            configuration: configuration,
            destination: destination,
            derivedDataPath: fs.absolutePath(derivedDataPath, relativeTo: cwd),
            xcodebuildArguments: xcodeArgs,
            appLaunch: appLaunch
        )
    }

    private func readConfig(at path: String) throws -> SweetDeckConfig {
        do {
            let data = try fs.readData(at: path)
            return try SweetDeckJSON.decode(SweetDeckConfig.self, from: data)
        } catch {
            throw SweetDeckError(code: .config, message: "Failed to parse config JSON", details: ["path": path, "error": "\(error)"])
        }
    }

    private func merge(base: SweetDeckConfig, override: SweetDeckConfig) -> SweetDeckConfig {
        var result = base
        if let project = override.project { result.project = project }
        if let scheme = override.scheme { result.scheme = scheme }
        if let schemes = override.schemes { result.schemes = schemes }
        if let defaultScheme = override.defaultScheme { result.defaultScheme = defaultScheme }
        if let configuration = override.configuration { result.configuration = configuration }
        if let destination = override.destination { result.destination = destination }
        if let derived = override.derivedDataPath { result.derivedDataPath = derived }
        if let args = override.xcodebuildArguments { result.xcodebuildArguments = (base.xcodebuildArguments ?? []) + args }
        if let app = override.appLaunch {
            var mergedApp = base.appLaunch ?? SweetDeckAppLaunch()
            if let bid = app.bundleIdentifier { mergedApp.bundleIdentifier = bid }
            if !app.arguments.isEmpty { mergedApp.arguments = app.arguments }
            if !app.environment.isEmpty {
                var env = mergedApp.environment
                for (k, v) in app.environment { env[k] = v }
                mergedApp.environment = env
            }
            result.appLaunch = mergedApp
        }
        return result
    }

    public func derivedDataPathFromSettings(project: SweetDeckProjectRef, cwd: String) -> String? {
        let basePath = fs.absolutePath(project.path, relativeTo: cwd)
        let rootDir: String
        switch project.type ?? inferProjectType(from: basePath) {
        case .xcworkspace:
            rootDir = basePath
        case .xcodeproj:
            rootDir = URL(fileURLWithPath: basePath).deletingLastPathComponent().path
        }

        let candidates = workspaceSettingsPaths(project: project, cwd: cwd)
        for path in candidates {
            guard fs.fileExists(at: path), let data = try? fs.readData(at: path) else { continue }
            if let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
               let dict = plist as? [String: Any] {
                let workspaceRoot = workspaceRootDirectory(forSettingsPath: path) ?? rootDir
                let custom = (dict["CustomDerivedDataLocation"] as? String)
                    ?? (dict["DerivedDataCustomLocation"] as? String)

                if let style = dict["DerivedDataLocationStyle"] as? String {
                    if style == "Custom", let custom, !custom.isEmpty {
                        if custom.hasPrefix("/") { return custom }
                        return fs.absolutePath(custom, relativeTo: workspaceRoot)
                    }
                    if style == "Workspace" || style == "WorkspaceRelativePath" {
                        let rel = (custom?.isEmpty == false) ? custom! : "DerivedData"
                        return fs.absolutePath(rel, relativeTo: workspaceRoot)
                    }
                } else if let styleInt = dict["DerivedDataLocationStyle"] as? Int {
                    if let custom, !custom.isEmpty {
                        if custom.hasPrefix("/") { return custom }
                        return fs.absolutePath(custom, relativeTo: workspaceRoot)
                    }
                    if styleInt == 2 {
                        return fs.absolutePath("DerivedData", relativeTo: workspaceRoot)
                    }
                }
            }
        }
        return nil
    }

    private func workspaceSettingsPaths(project: SweetDeckProjectRef, cwd: String) -> [String] {
        let basePath = fs.absolutePath(project.path, relativeTo: cwd)
        var settingsPaths: [String]
        switch project.type ?? inferProjectType(from: basePath) {
        case .xcworkspace:
            settingsPaths = [
                fs.absolutePath("xcshareddata/WorkspaceSettings.xcsettings", relativeTo: basePath)
            ] + userWorkspaceSettings(basePath: basePath)
        case .xcodeproj:
            let workspacePath = fs.absolutePath("project.xcworkspace", relativeTo: basePath)
            let siblingWorkspace = basePath.hasSuffix(".xcodeproj")
                ? String(basePath.dropLast(".xcodeproj".count)) + ".xcworkspace"
                : nil
            settingsPaths = [
                fs.absolutePath("xcshareddata/WorkspaceSettings.xcsettings", relativeTo: workspacePath)
            ] + userWorkspaceSettings(basePath: workspacePath)
            if let siblingWorkspace {
                settingsPaths += [
                    fs.absolutePath("xcshareddata/WorkspaceSettings.xcsettings", relativeTo: siblingWorkspace)
                ] + userWorkspaceSettings(basePath: siblingWorkspace)
            }
        }
        return settingsPaths
    }

    private func userWorkspaceSettings(basePath: String) -> [String] {
        let xcuserdata = fs.absolutePath("xcuserdata", relativeTo: basePath)
        guard let entries = try? fs.listDirectory(at: xcuserdata) else { return [] }
        return entries.map { fs.absolutePath("\($0)/WorkspaceSettings.xcsettings", relativeTo: xcuserdata) }
    }

    private func workspaceRootDirectory(forSettingsPath path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents
        if let idx = components.lastIndex(of: "xcshareddata") ?? components.lastIndex(of: "xcuserdata") {
            return NSString.path(withComponents: Array(components.prefix(idx)))
        }
        return url.deletingLastPathComponent().path
    }

    private func inferProjectType(from path: String) -> SweetDeckProjectType {
        if path.hasSuffix(".xcworkspace") { return .xcworkspace }
        return .xcodeproj
    }
}
