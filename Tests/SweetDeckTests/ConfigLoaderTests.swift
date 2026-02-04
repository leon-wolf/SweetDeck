import XCTest
@testable import SweetDeckUseCases
import SweetDeckDomain
import SweetDeckInfra

final class ConfigLoaderTests: XCTestCase {
    func testPrefersSweetdeckConfigOverFlowdeckConfig() throws {
        let fs = SweetDeckFileSystem()
        let tmp = try makeTempDir()
        defer { try? fs.removeItem(at: tmp) }

        try fs.createDirectory(at: fs.absolutePath(".sweetdeck", relativeTo: tmp))
        try fs.createDirectory(at: fs.absolutePath(".flowdeck", relativeTo: tmp))

        let sweet = SweetDeckConfig(project: .init(path: "App.xcodeproj", type: .xcodeproj), scheme: "Sweet")
        let flow = SweetDeckConfig(project: .init(path: "App.xcodeproj", type: .xcodeproj), scheme: "Flow")
        try fs.writeAtomic(data: SweetDeckJSON.encodePretty(sweet), to: fs.absolutePath(".sweetdeck/config.json", relativeTo: tmp))
        try fs.writeAtomic(data: SweetDeckJSON.encodePretty(flow), to: fs.absolutePath(".flowdeck/config.json", relativeTo: tmp))

        let nested = fs.absolutePath("a/b/c", relativeTo: tmp)
        try fs.createDirectory(at: nested)

        let loader = SweetDeckConfigLoader(fs: fs, console: SweetDeckConsole(outputFormat: .human, verbose: false, quiet: true), forcedConfigPath: nil)
        let loaded = try loader.load(from: nested)
        XCTAssertEqual(loaded.loadedFrom, ".sweetdeck/config.json")
        XCTAssertEqual(loaded.config.scheme, "Sweet")
    }

    func testForcedConfigOverridesDiscovery() throws {
        let fs = SweetDeckFileSystem()
        let tmp = try makeTempDir()
        defer { try? fs.removeItem(at: tmp) }

        let path = fs.absolutePath("config.json", relativeTo: tmp)
        let cfg = SweetDeckConfig(project: .init(path: "App.xcodeproj", type: .xcodeproj), scheme: "S")
        try fs.writeAtomic(data: SweetDeckJSON.encodePretty(cfg), to: path)

        let loader = SweetDeckConfigLoader(fs: fs, console: SweetDeckConsole(outputFormat: .human, verbose: false, quiet: true), forcedConfigPath: path)
        let loaded = try loader.load(from: tmp)
        XCTAssertEqual(loaded.configPath, path)
        XCTAssertEqual(loaded.config.scheme, "S")
    }

    func testSchemePriorityWithDefaultAndSchemes() throws {
        let fs = SweetDeckFileSystem()
        let tmp = try makeTempDir()
        defer { try? fs.removeItem(at: tmp) }

        let cfg = SweetDeckConfig(
            project: .init(path: "App.xcodeproj", type: .xcodeproj),
            scheme: "A",
            schemes: ["A", "B"],
            defaultScheme: "B"
        )
        let path = fs.absolutePath(".sweetdeck/config.json", relativeTo: tmp)
        try fs.createDirectory(at: fs.absolutePath(".sweetdeck", relativeTo: tmp))
        try fs.writeAtomic(data: SweetDeckJSON.encodePretty(cfg), to: path)

        let loader = SweetDeckConfigLoader(fs: fs, console: SweetDeckConsole(outputFormat: .human, verbose: false, quiet: true), forcedConfigPath: nil)
        let loaded = try loader.load(from: tmp)
        let ctx = try loader.resolveContext(loaded: loaded, cwd: tmp, overrides: SweetDeckConfig())
        XCTAssertEqual(ctx.scheme, "B")

        let ctxOverride = try loader.resolveContext(loaded: loaded, cwd: tmp, overrides: SweetDeckConfig(scheme: "C"))
        XCTAssertEqual(ctxOverride.scheme, "C")
    }

    func testSchemeFallsBackToSchemesList() throws {
        let fs = SweetDeckFileSystem()
        let tmp = try makeTempDir()
        defer { try? fs.removeItem(at: tmp) }

        let cfg = SweetDeckConfig(
            project: .init(path: "App.xcodeproj", type: .xcodeproj),
            schemes: ["A", "B"]
        )
        let path = fs.absolutePath(".sweetdeck/config.json", relativeTo: tmp)
        try fs.createDirectory(at: fs.absolutePath(".sweetdeck", relativeTo: tmp))
        try fs.writeAtomic(data: SweetDeckJSON.encodePretty(cfg), to: path)

        let loader = SweetDeckConfigLoader(fs: fs, console: SweetDeckConsole(outputFormat: .human, verbose: false, quiet: true), forcedConfigPath: nil)
        let loaded = try loader.load(from: tmp)
        let ctx = try loader.resolveContext(loaded: loaded, cwd: tmp, overrides: SweetDeckConfig())
        XCTAssertEqual(ctx.scheme, "A")
    }

    private func makeTempDir() throws -> String {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("sweetdeck-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }
}
