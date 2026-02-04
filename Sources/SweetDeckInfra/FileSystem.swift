import Foundation
import SweetDeckDomain

public protocol SweetDeckFileSysteming {
    func fileExists(at path: String) -> Bool
    func directoryExists(at path: String) -> Bool
    func readData(at path: String) throws -> Data
    func writeAtomic(data: Data, to path: String) throws
    func createDirectory(at path: String) throws
    func removeItem(at path: String) throws
    func listDirectory(at path: String) throws -> [String]
    func currentDirectory() -> String
    func absolutePath(_ path: String, relativeTo base: String) -> String
    func findUpward(from startDirectory: String, candidates: [String]) -> (foundPath: String, matchedName: String)?
    func walkFiles(root: String, includeExtensions: Set<String>, excludeDirectoryNames: Set<String>) -> [String]
}

public final class SweetDeckFileSystem: SweetDeckFileSysteming {
    private let fm = FileManager.default

    public init() {}

    public func fileExists(at path: String) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &isDir) && !isDir.boolValue
    }

    public func directoryExists(at path: String) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    public func readData(at path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    public func writeAtomic(data: Data, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    public func createDirectory(at path: String) throws {
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    public func removeItem(at path: String) throws {
        try fm.removeItem(atPath: path)
    }

    public func listDirectory(at path: String) throws -> [String] {
        try fm.contentsOfDirectory(atPath: path)
    }

    public func currentDirectory() -> String {
        fm.currentDirectoryPath
    }

    public func absolutePath(_ path: String, relativeTo base: String) -> String {
        if path.hasPrefix("/") { return path }
        return URL(fileURLWithPath: base).appendingPathComponent(path).standardizedFileURL.path
    }

    public func findUpward(from startDirectory: String, candidates: [String]) -> (foundPath: String, matchedName: String)? {
        var current = URL(fileURLWithPath: startDirectory).standardizedFileURL
        while true {
            for candidate in candidates {
                let found = current.appendingPathComponent(candidate).path
                if fm.fileExists(atPath: found) {
                    return (found, candidate)
                }
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    public func walkFiles(root: String, includeExtensions: Set<String>, excludeDirectoryNames: Set<String>) -> [String] {
        let rootURL = URL(fileURLWithPath: root)
        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var results: [String] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if excludeDirectoryNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            if includeExtensions.contains(url.pathExtension.lowercased()) {
                results.append(url.path)
            }
        }
        return results
    }
}
