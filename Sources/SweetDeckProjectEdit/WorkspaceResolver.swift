import Foundation
import SweetDeckDomain
import SweetDeckInfra

public enum SweetDeckWorkspaceResolver {
    public static func resolveEditableXcodeprojPath(
        fs: SweetDeckFileSysteming,
        project: SweetDeckProjectRef,
        cwd: String
    ) throws -> String {
        let projectPath = fs.absolutePath(project.path, relativeTo: cwd)
        let type = project.type ?? (projectPath.hasSuffix(".xcworkspace") ? .xcworkspace : .xcodeproj)
        switch type {
        case .xcodeproj:
            return projectPath
        case .xcworkspace:
            let workspaceDir = URL(fileURLWithPath: projectPath).path
            let contents = URL(fileURLWithPath: workspaceDir).appendingPathComponent("contents.xcworkspacedata").path
            guard fs.fileExists(at: contents) else {
                throw SweetDeckError(code: .projectEditFailed, message: "Workspace contents not found", details: ["path": contents])
            }
            let data = try fs.readData(at: contents)
            guard let xml = String(data: data, encoding: .utf8) else {
                throw SweetDeckError(code: .projectEditFailed, message: "Failed to read workspace contents", details: ["path": contents])
            }
            if let xcodeprojRel = firstXcodeprojLocation(from: xml) {
                let resolved = resolveWorkspaceLocation(xcodeprojRel, workspacePath: workspaceDir)
                return fs.absolutePath(resolved, relativeTo: workspaceDir)
            }
            throw SweetDeckError(code: .projectEditFailed, message: "Could not find any .xcodeproj inside workspace", details: ["workspace": projectPath])
        }
    }

    private static func firstXcodeprojLocation(from xml: String) -> String? {
        // FileRef location values look like:
        //   location="group:MyApp.xcodeproj"
        //   location="absolute:/path/to/MyApp.xcodeproj"
        //   location="container:MyApp.xcodeproj"
        let re = try? NSRegularExpression(pattern: #"location\s*=\s*"([^"]*\.xcodeproj)""#)
        let ns = xml as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = re?.firstMatch(in: xml, options: [], range: range) else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func resolveWorkspaceLocation(_ location: String, workspacePath: String) -> String {
        let parts = location.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return location }
        let scheme = parts[0]
        let value = parts[1]
        switch scheme {
        case "absolute":
            return value
        case "group", "container":
            // Workspace file is a directory (*.xcworkspace). group/container refs are relative to its parent directory.
            let base = URL(fileURLWithPath: workspacePath).deletingLastPathComponent()
            return base.appendingPathComponent(value).standardizedFileURL.path
        default:
            return value
        }
    }
}
