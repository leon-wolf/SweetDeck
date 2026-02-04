import Foundation
import SweetDeckDomain
import SweetDeckInfra
import SweetDeckXcode
import SweetDeckProjectEdit

public struct SweetDeckGlobalOptions: Sendable {
    public var cwd: String
    public var configPath: String?
    public var output: SweetDeckOutputFormat
    public var verbose: Bool
    public var quiet: Bool

    public init(cwd: String, configPath: String?, output: SweetDeckOutputFormat, verbose: Bool, quiet: Bool) {
        self.cwd = cwd
        self.configPath = configPath
        self.output = output
        self.verbose = verbose
        self.quiet = quiet
    }
}

public final class SweetDeckRuntime: @unchecked Sendable {
    public let cwd: String
    public let fs: SweetDeckFileSysteming
    public let process: SweetDeckProcessRunning
    public let console: SweetDeckConsole
    public let configLoader: SweetDeckConfigLoader
    public let xcodebuild: SweetDeckXcodeBuilding
    public let simctl: SweetDeckSimulatorControlling
    public let devicectl: SweetDeckDeviceControlling
    public let projectEdit: SweetDeckProjectEditing
    public let state: SweetDeckStateStore

    public init(options: SweetDeckGlobalOptions) {
        self.cwd = options.cwd
        self.fs = SweetDeckFileSystem()
        self.console = SweetDeckConsole(outputFormat: options.output, verbose: options.verbose, quiet: options.quiet)
        self.process = SweetDeckProcessRunner()
        self.configLoader = SweetDeckConfigLoader(fs: fs, console: console, forcedConfigPath: options.configPath)
        self.xcodebuild = SweetDeckXcodebuildClient(process: process, console: console)
        self.simctl = SweetDeckSimctlClient(process: process, console: console)
        self.devicectl = SweetDeckDevicectlClient(process: process, console: console)
        self.projectEdit = SweetDeckProjectEditor(fs: fs, console: console, process: process, xcodebuild: self.xcodebuild)
        self.state = SweetDeckStateStore(fs: fs, console: console)
    }
}
