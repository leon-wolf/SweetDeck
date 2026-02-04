import XCTest
import SweetDeckUseCases
import SweetDeckInfra

final class TestDiscoveryTests: XCTestCase {
    func testDiscoversXCTestAndSwiftTesting() throws {
        let fs = SweetDeckFileSystem()
        let tmp = try makeTempDir()
        defer { try? fs.removeItem(at: tmp) }

        let file = fs.absolutePath("Tests/SampleTests.swift", relativeTo: tmp)
        try fs.createDirectory(at: URL(fileURLWithPath: file).deletingLastPathComponent().path)

        let content = """
        import XCTest
        import Testing

        final class FooTests: XCTestCase {
            func testA() {}
            func testB() {}
        }

        @Suite
        struct BarSuite {
            @Test func bar() {}
        }
        """
        try fs.writeAtomic(data: content.data(using: .utf8)!, to: file)

        let tests = SweetDeckTestDiscovery.discover(fs: fs, root: tmp)
        XCTAssertTrue(tests.contains(where: { $0.suite == "FooTests" && $0.testName == "testA" }))
        XCTAssertTrue(tests.contains(where: { $0.suite == "FooTests" && $0.testName == "testB" }))
        XCTAssertTrue(tests.contains(where: { $0.suite == "BarSuite" && $0.testName == "bar" }))
    }

    private func makeTempDir() throws -> String {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("sweetdeck-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }
}
