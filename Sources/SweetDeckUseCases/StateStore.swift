import Foundation
import SweetDeckDomain
import SweetDeckInfra

public struct SweetDeckDeviceLaunchState: Codable, Hashable, Sendable {
    public var device: String
    public var bundleId: String
    public var pid: Int
    public var timestamp: Date

    public init(device: String, bundleId: String, pid: Int, timestamp: Date) {
        self.device = device
        self.bundleId = bundleId
        self.pid = pid
        self.timestamp = timestamp
    }
}

public final class SweetDeckStateStore: @unchecked Sendable {
    private let fs: SweetDeckFileSysteming
    private let console: SweetDeckConsole

    public init(fs: SweetDeckFileSysteming, console: SweetDeckConsole) {
        self.fs = fs
        self.console = console
    }

    public func loadState(at cwd: String) -> [SweetDeckDeviceLaunchState] {
        let path = fs.absolutePath(".sweetdeck/state.json", relativeTo: cwd)
        guard fs.fileExists(at: path), let data = try? fs.readData(at: path) else { return [] }
        return (try? SweetDeckJSON.decode([SweetDeckDeviceLaunchState].self, from: data)) ?? []
    }

    public func recordDeviceLaunch(cwd: String, state: SweetDeckDeviceLaunchState) {
        var all = loadState(at: cwd)
        all.removeAll { $0.device == state.device && $0.bundleId == state.bundleId }
        all.append(state)
        all.sort { $0.timestamp > $1.timestamp }
        let path = fs.absolutePath(".sweetdeck/state.json", relativeTo: cwd)
        do {
            let data = try SweetDeckJSON.encodePretty(all)
            try fs.writeAtomic(data: data, to: path)
        } catch {
            console.warn("Failed to write state: \(error)")
        }
    }

    public func findPID(cwd: String, device: String, bundleId: String) -> Int? {
        loadState(at: cwd).first(where: { $0.device == device && $0.bundleId == bundleId })?.pid
    }
}
