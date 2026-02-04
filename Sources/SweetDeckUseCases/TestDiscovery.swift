import Foundation
import SweetDeckDomain
import SweetDeckInfra

public enum SweetDeckTestFramework: String, Codable, Sendable {
    case xctest
    case swiftTesting
}

public struct SweetDeckDiscoveredTest: Codable, Hashable, Sendable {
    public var file: String
    public var line: Int
    public var framework: SweetDeckTestFramework
    public var suite: String
    public var testName: String
}

public enum SweetDeckTestDiscovery {
    public static func discover(fs: SweetDeckFileSysteming, root: String) -> [SweetDeckDiscoveredTest] {
        let exclude: Set<String> = [".git", ".build", ".swiftpm", "DerivedData", ".sweetdeck"]
        let files = fs.walkFiles(root: root, includeExtensions: ["swift"], excludeDirectoryNames: exclude)
        var results: [SweetDeckDiscoveredTest] = []
        for file in files {
            guard let content = try? String(contentsOfFile: file) else { continue }
            results += discoverInFile(path: file, content: content)
        }
        return results.sorted { ($0.file, $0.suite, $0.testName, $0.line) < ($1.file, $1.suite, $1.testName, $1.line) }
    }

    private static func discoverInFile(path: String, content: String) -> [SweetDeckDiscoveredTest] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var found: [SweetDeckDiscoveredTest] = []

        // XCTest: track current XCTestCase class and collect test funcs.
        let xctestClass = try? NSRegularExpression(pattern: #"^\s*(final\s+)?class\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*XCTestCase\b"#)
        let xctestFunc = try? NSRegularExpression(pattern: #"^\s*func\s+(test[A-Za-z0-9_]+)\s*\("#)
        var currentXCTestSuite: String?

        // Swift Testing: track @Suite type and @Test functions.
        let suiteAttr = try? NSRegularExpression(pattern: #"@Suite\b"#)
        let typeDecl = try? NSRegularExpression(pattern: #"\b(struct|class|enum)\s+([A-Za-z_][A-Za-z0-9_]*)\b"#)
        let testAttr = try? NSRegularExpression(pattern: #"@Test\b"#)
        let funcDecl = try? NSRegularExpression(pattern: #"\bfunc\s+([A-Za-z_][A-Za-z0-9_]*)\s*\("#)
        var pendingSuiteAttribute = false
        var pendingTestAttribute = false
        var currentSwiftTestingSuite: String?
        var lastTypeName: String?

        for (idx, line) in lines.enumerated() {
            let nsline = line as NSString
            let range = NSRange(location: 0, length: nsline.length)

            if let re = xctestClass, let m = re.firstMatch(in: line, options: [], range: range) {
                currentXCTestSuite = nsline.substring(with: m.range(at: 2))
            }
            if let suiteAttr, suiteAttr.firstMatch(in: line, options: [], range: range) != nil {
                pendingSuiteAttribute = true
            }
            if let typeDecl, let m = typeDecl.firstMatch(in: line, options: [], range: range) {
                lastTypeName = nsline.substring(with: m.range(at: 2))
            }
            if pendingSuiteAttribute, let typeDecl, let m = typeDecl.firstMatch(in: line, options: [], range: range) {
                currentSwiftTestingSuite = nsline.substring(with: m.range(at: 2))
                pendingSuiteAttribute = false
            }

            if let testAttr, testAttr.firstMatch(in: line, options: [], range: range) != nil {
                pendingTestAttribute = true
            }
            if pendingTestAttribute, let funcDecl, let m = funcDecl.firstMatch(in: line, options: [], range: range) {
                let name = nsline.substring(with: m.range(at: 1))
                let suite = currentSwiftTestingSuite ?? lastTypeName ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                found.append(SweetDeckDiscoveredTest(file: path, line: idx + 1, framework: .swiftTesting, suite: suite, testName: name))
                pendingTestAttribute = false
            }

            if let re = xctestFunc, let m = re.firstMatch(in: line, options: [], range: range) {
                let name = nsline.substring(with: m.range(at: 1))
                let suite = currentXCTestSuite ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                found.append(SweetDeckDiscoveredTest(file: path, line: idx + 1, framework: .xctest, suite: suite, testName: name))
            }
        }
        return found
    }
}
