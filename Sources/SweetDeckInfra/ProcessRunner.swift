import Foundation
import SweetDeckDomain

public struct SweetDeckCommand {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]

    public init(executable: String, arguments: [String] = [], environment: [String: String] = [:]) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }

    public var pretty: String {
        ([executable] + arguments).joined(separator: " ")
    }
}

public struct SweetDeckRunResult {
    public var exitCode: Int32
    public var stdout: Data
    public var stderr: Data
    public var durationMs: Int64
}

public protocol SweetDeckProcessRunning {
    func runCapture(_ command: SweetDeckCommand, cwd: String?) throws -> SweetDeckRunResult
    func runStreaming(_ command: SweetDeckCommand, cwd: String?, streamToStdout: Bool, streamToStderr: Bool) throws -> SweetDeckRunResult
}

public final class SweetDeckProcessRunner: SweetDeckProcessRunning {
    nonisolated(unsafe) private static var signalInstalled = false
    nonisolated(unsafe) fileprivate static var currentPid: pid_t = 0

    public init() {}

    public func runCapture(_ command: SweetDeckCommand, cwd: String?) throws -> SweetDeckRunResult {
        try SweetDeckTempFiles.withTemporaryFile(prefix: "sweetdeck-stdout-", suffix: ".log") { stdoutPath in
            try SweetDeckTempFiles.withTemporaryFile(prefix: "sweetdeck-stderr-", suffix: ".log") { stderrPath in
                let start = DispatchTime.now().uptimeNanoseconds

                let process = Process()
                process.executableURL = URL(fileURLWithPath: command.executable)
                process.arguments = command.arguments
                if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

                var env = ProcessInfo.processInfo.environment
                for (k, v) in command.environment { env[k] = v }
                process.environment = env

                FileManager.default.createFile(atPath: stdoutPath, contents: nil)
                FileManager.default.createFile(atPath: stderrPath, contents: nil)
                let stdoutHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: stdoutPath))
                let stderrHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: stderrPath))
                defer {
                    try? stdoutHandle.close()
                    try? stderrHandle.close()
                }
                process.standardOutput = stdoutHandle
                process.standardError = stderrHandle

                do {
                    try process.run()
                } catch {
                    throw SweetDeckError(code: .toolNotFound, message: "Failed to run \(command.executable)", details: ["error": "\(error)"])
                }
                process.waitUntilExit()

                let end = DispatchTime.now().uptimeNanoseconds
                let durationMs = Int64((end - start) / 1_000_000)

                let out = (try? Data(contentsOf: URL(fileURLWithPath: stdoutPath))) ?? Data()
                let err = (try? Data(contentsOf: URL(fileURLWithPath: stderrPath))) ?? Data()
                return SweetDeckRunResult(exitCode: process.terminationStatus, stdout: out, stderr: err, durationMs: durationMs)
            }
        }
    }

    public func runStreaming(
        _ command: SweetDeckCommand,
        cwd: String?,
        streamToStdout: Bool,
        streamToStderr: Bool
    ) throws -> SweetDeckRunResult {
        let start = DispatchTime.now().uptimeNanoseconds

        let process = Process()
        SweetDeckProcessRunner.installSignalHandler()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

        var env = ProcessInfo.processInfo.environment
        for (k, v) in command.environment { env[k] = v }
        process.environment = env

        // When streaming, wire directly to our stdio to avoid pipe-buffer deadlocks and Swift 6 data-race checks.
        // Captured output is returned empty in streaming mode.
        if streamToStdout {
            process.standardOutput = FileHandle.standardOutput
        } else {
            process.standardOutput = Pipe()
        }
        if streamToStderr {
            process.standardError = FileHandle.standardError
        } else {
            process.standardError = Pipe()
        }

        do {
            try process.run()
        } catch {
            throw SweetDeckError(code: .toolNotFound, message: "Failed to run \(command.executable)", details: ["error": "\(error)"])
        }
        SweetDeckProcessRunner.currentPid = process.processIdentifier

        process.waitUntilExit()

        SweetDeckProcessRunner.currentPid = 0

        let end = DispatchTime.now().uptimeNanoseconds
        let durationMs = Int64((end - start) / 1_000_000)

        let out: Data
        if streamToStdout { out = Data() }
        else if let pipe = process.standardOutput as? Pipe { out = pipe.fileHandleForReading.readDataToEndOfFile() }
        else { out = Data() }

        let err: Data
        if streamToStderr { err = Data() }
        else if let pipe = process.standardError as? Pipe { err = pipe.fileHandleForReading.readDataToEndOfFile() }
        else { err = Data() }

        return SweetDeckRunResult(exitCode: process.terminationStatus, stdout: out, stderr: err, durationMs: durationMs)
    }

    private static func installSignalHandler() {
        guard !signalInstalled else { return }
        signalInstalled = true
        signal(SIGINT, sweetdeckSigintHandler)
    }
}

private func sweetdeckSigintHandler(_ signal: Int32) -> Void {
    let pid = SweetDeckProcessRunner.currentPid
    if pid != 0 {
        _ = kill(pid, SIGINT)
    }
    exit(130)
}
