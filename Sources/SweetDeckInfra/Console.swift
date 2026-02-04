import Foundation
import SweetDeckDomain

public struct SweetDeckConsole: Sendable {
    public var outputFormat: SweetDeckOutputFormat
    public var verbose: Bool
    public var quiet: Bool

    public init(outputFormat: SweetDeckOutputFormat, verbose: Bool, quiet: Bool) {
        self.outputFormat = outputFormat
        self.verbose = verbose
        self.quiet = quiet
    }

    public var shouldSpin: Bool {
        outputFormat == .human && !quiet && !verbose
    }

    public func info(_ message: String) {
        guard !quiet, outputFormat == .human else { return }
        FileHandle.standardOutput.write((format("✅", .green, message) + "\n").data(using: .utf8)!)
    }

    public func warn(_ message: String) {
        guard !quiet, outputFormat == .human else { return }
        FileHandle.standardError.write((format("⚠️", .yellow, "warning: \(message)") + "\n").data(using: .utf8)!)
    }

    public func error(_ message: String) {
        guard outputFormat == .human else { return }
        FileHandle.standardError.write((format("❌", .red, "error: \(message)") + "\n").data(using: .utf8)!)
    }

    public func debug(_ message: String) {
        guard verbose, !quiet, outputFormat == .human else { return }
        FileHandle.standardError.write((format("🧩", .cyan, "debug: \(message)") + "\n").data(using: .utf8)!)
    }

    private enum AnsiColor: String {
        case red = "\u{001B}[31m"
        case green = "\u{001B}[32m"
        case yellow = "\u{001B}[33m"
        case cyan = "\u{001B}[36m"
    }

    private func format(_ emoji: String, _ color: AnsiColor, _ message: String) -> String {
        "\(color.rawValue)\(emoji) \(message)\u{001B}[0m"
    }
}
