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

public struct SweetDeckSimulatorLaunchState: Codable, Hashable, Sendable {
    public var simulatorUDID: String
    public var bundleId: String
    public var timestamp: Date

    public init(simulatorUDID: String, bundleId: String, timestamp: Date) {
        self.simulatorUDID = simulatorUDID
        self.bundleId = bundleId
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

    public func loadState(at cwd: String) -> SweetDeckLaunchState {
        let path = fs.absolutePath(".sweetdeck/state.json", relativeTo: cwd)
        guard fs.fileExists(at: path), let data = try? fs.readData(at: path) else { return .empty }
        if let typed = try? SweetDeckJSON.decode(SweetDeckLaunchState.self, from: data) {
            return typed
        }
        if let legacy = try? SweetDeckJSON.decode([SweetDeckDeviceLaunchState].self, from: data) {
            return SweetDeckLaunchState(devices: legacy, simulators: [])
        }
        return .empty
    }

    public func recordDeviceLaunch(cwd: String, state: SweetDeckDeviceLaunchState) {
        var store = loadState(at: cwd)
        store.devices.removeAll { $0.device == state.device && $0.bundleId == state.bundleId }
        store.devices.append(state)
        store.devices.sort { $0.timestamp > $1.timestamp }
        writeState(store, cwd: cwd)
    }

    public func recordSimulatorLaunch(cwd: String, state: SweetDeckSimulatorLaunchState) {
        var store = loadState(at: cwd)
        store.simulators.removeAll { $0.simulatorUDID == state.simulatorUDID && $0.bundleId == state.bundleId }
        store.simulators.append(state)
        store.simulators.sort { $0.timestamp > $1.timestamp }
        writeState(store, cwd: cwd)
    }

    public func findPID(cwd: String, device: String, bundleId: String) -> Int? {
        loadState(at: cwd).devices.first(where: { $0.device == device && $0.bundleId == bundleId })?.pid
    }

    public func findLastSimulatorBundleId(cwd: String, simulatorUDID: String) -> String? {
        loadState(at: cwd).simulators.first(where: { $0.simulatorUDID == simulatorUDID })?.bundleId
    }

    public func findLastDeviceLaunch(cwd: String, bundleId: String) -> SweetDeckDeviceLaunchState? {
        loadState(at: cwd).devices.first(where: { $0.bundleId == bundleId })
    }

    private func writeState(_ state: SweetDeckLaunchState, cwd: String) {
        let path = fs.absolutePath(".sweetdeck/state.json", relativeTo: cwd)
        do {
            let data = try SweetDeckJSON.encodePretty(state)
            try fs.writeAtomic(data: data, to: path)
        } catch {
            console.warn("Failed to write state: \(error)")
        }
    }
}

public struct SweetDeckLaunchState: Codable, Hashable, Sendable {
    public var devices: [SweetDeckDeviceLaunchState]
    public var simulators: [SweetDeckSimulatorLaunchState]

    public init(devices: [SweetDeckDeviceLaunchState], simulators: [SweetDeckSimulatorLaunchState]) {
        self.devices = devices
        self.simulators = simulators
    }

    public static var empty: SweetDeckLaunchState {
        SweetDeckLaunchState(devices: [], simulators: [])
    }
}
