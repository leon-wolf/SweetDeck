import Foundation

public enum SweetDeckTempFiles {
    public static func withTemporaryFile<T>(prefix: String, suffix: String, _ body: (String) throws -> T) throws -> T {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let name = prefix + UUID().uuidString + suffix
        let path = directory.appendingPathComponent(name).path
        FileManager.default.createFile(atPath: path, contents: nil)
        defer { try? FileManager.default.removeItem(atPath: path) }
        return try body(path)
    }
}

