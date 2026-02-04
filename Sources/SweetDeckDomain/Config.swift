import Foundation

public enum SweetDeckOutputFormat: String, Codable, CaseIterable, Sendable {
    case human
    case json
}

public enum SweetDeckProjectType: String, Codable, CaseIterable, Sendable {
    case xcworkspace
    case xcodeproj
}

public struct SweetDeckProjectRef: Codable, Hashable, Sendable {
    public var path: String
    public var type: SweetDeckProjectType?

    public init(path: String, type: SweetDeckProjectType? = nil) {
        self.path = path
        self.type = type
    }
}

public struct SweetDeckAppLaunch: Codable, Hashable, Sendable {
    public var bundleIdentifier: String?
    public var arguments: [String]
    public var environment: [String: String]

    public init(bundleIdentifier: String? = nil, arguments: [String] = [], environment: [String: String] = [:]) {
        self.bundleIdentifier = bundleIdentifier
        self.arguments = arguments
        self.environment = environment
    }
}

/// Read-compatible with FlowDeck's config shape (we also accept missing fields).
public struct SweetDeckConfig: Codable, Hashable, Sendable {
    public var project: SweetDeckProjectRef?
    public var scheme: String?
    public var schemes: [String]?
    public var defaultScheme: String?
    public var configuration: String?
    public var destination: String?
    public var derivedDataPath: String?
    public var xcodebuildArguments: [String]?
    public var appLaunch: SweetDeckAppLaunch?

    public init(
        project: SweetDeckProjectRef? = nil,
        scheme: String? = nil,
        schemes: [String]? = nil,
        defaultScheme: String? = nil,
        configuration: String? = nil,
        destination: String? = nil,
        derivedDataPath: String? = nil,
        xcodebuildArguments: [String]? = nil,
        appLaunch: SweetDeckAppLaunch? = nil
    ) {
        self.project = project
        self.scheme = scheme
        self.schemes = schemes
        self.defaultScheme = defaultScheme
        self.configuration = configuration
        self.destination = destination
        self.derivedDataPath = derivedDataPath
        self.xcodebuildArguments = xcodebuildArguments
        self.appLaunch = appLaunch
    }
}

public struct SweetDeckResolvedContext: Codable, Hashable, Sendable {
    public var configPath: String?
    public var loadedFrom: String?

    public var project: SweetDeckProjectRef
    public var scheme: String
    public var configuration: String
    public var destination: String
    public var derivedDataPath: String
    public var xcodebuildArguments: [String]
    public var appLaunch: SweetDeckAppLaunch

    public init(
        configPath: String?,
        loadedFrom: String?,
        project: SweetDeckProjectRef,
        scheme: String,
        configuration: String,
        destination: String,
        derivedDataPath: String,
        xcodebuildArguments: [String],
        appLaunch: SweetDeckAppLaunch
    ) {
        self.configPath = configPath
        self.loadedFrom = loadedFrom
        self.project = project
        self.scheme = scheme
        self.configuration = configuration
        self.destination = destination
        self.derivedDataPath = derivedDataPath
        self.xcodebuildArguments = xcodebuildArguments
        self.appLaunch = appLaunch
    }
}
