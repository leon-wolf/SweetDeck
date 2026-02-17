import Foundation
import SweetDeckDomain
import SweetDeckInfra
import SweetDeckUseCases
import ArgumentParser

struct SweetDeckCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sweetdeck",
        abstract: "FlowDeck-like CLI for Xcode builds, simulators, and workflow automation.",
        version: SweetDeckVersion.current,
        subcommands: [
            Init.self,
            Context.self,
            Build.self,
            Run.self,
            Clean.self,
            Test.self,
            Logs.self,
            Stop.self,
            Apps.self,
            Simulator.self,
            Device.self,
            Project.self,
            License.self,
            Update.self,
        ]
    )

    func run() throws {}
}

enum OutputFormatArg: String, ExpressibleByArgument, CaseIterable {
    case human
    case json

    var domain: SweetDeckOutputFormat {
        switch self {
        case .human: return .human
        case .json: return .json
        }
    }
}

enum ProjectTypeArg: String, ExpressibleByArgument, CaseIterable {
    case xcworkspace
    case xcodeproj

    var domain: SweetDeckProjectType {
        switch self {
        case .xcworkspace: return .xcworkspace
        case .xcodeproj: return .xcodeproj
        }
    }
}

struct GlobalOptions: ParsableArguments {
    @Option(help: "Run as if invoked from this directory.")
    var cwd: String?

    @Option(help: "Explicit config file path (overrides auto-discovery).")
    var config: String?

    @Option(help: "Output format.")
    var output: OutputFormatArg = .human

    @Flag(help: "Extra logs (prints full tool invocations + timing).")
    var verbose: Bool = false

    @Flag(help: "Suppress non-error output.")
    var quiet: Bool = false

    @Option(help: "Override scheme for this invocation.")
    var scheme: String?

    @Flag(name: .customLong("pick-scheme"), help: "Deprecated interactive flag. Use --scheme <name>.")
    var pickScheme: Bool = false

    func makeRuntime() -> SweetDeckRuntime {
        let fs = SweetDeckFileSystem()
        let baseCwd = cwd.map { fs.absolutePath($0, relativeTo: fs.currentDirectory()) } ?? fs.currentDirectory()
        return SweetDeckRuntime(
            options: SweetDeckGlobalOptions(
                cwd: baseCwd,
                configPath: config,
                output: output.domain,
                verbose: verbose,
                quiet: quiet
            )
        )
    }
}

extension ParsableCommand {
    func finishJSONSuccess(_ message: String) throws -> Never {
        let data = try SweetDeckJSON.encodePretty(SweetDeckJSONResponse<[String: String]>(ok: true, code: 0, message: message, details: nil))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
        throw ExitCode.success
    }

    func finishJSONSuccess<T: Encodable>(_ message: String, details: T? = nil) throws -> Never {
        let data = try SweetDeckJSON.encodePretty(SweetDeckJSONResponse(ok: true, code: 0, message: message, details: details))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
        throw ExitCode.success
    }

    func finishJSONError(_ error: SweetDeckError) throws -> Never {
        let data = try SweetDeckJSON.encodePretty(SweetDeckJSONResponse<[String: String]>(ok: false, code: error.code.rawValue, message: error.message, details: error.details))
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
        throw ExitCode(Int32(error.code.rawValue))
    }

    func mapError(_ error: Error) -> SweetDeckError {
        if let e = error as? SweetDeckError { return e }
        if let e = error as? ValidationError { return SweetDeckError(code: .usage, message: e.message) }
        return SweetDeckError(code: .unknown, message: "\(error)")
    }
}

SweetDeckCLI.main()
