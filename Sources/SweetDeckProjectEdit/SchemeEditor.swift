import Foundation
import SweetDeckDomain
import SweetDeckInfra

public enum SweetDeckSchemeEditor {
    public static func findSchemeFile(
        fs: SweetDeckFileSysteming,
        projectPath: String,
        projectType: SweetDeckProjectType,
        schemeName: String
    ) -> String? {
        let baseURL = URL(fileURLWithPath: projectPath)
        let sharedDir = baseURL.appendingPathComponent("xcshareddata/xcschemes", isDirectory: true).path
        let sharedFile = URL(fileURLWithPath: sharedDir).appendingPathComponent("\(schemeName).xcscheme").path
        if fs.fileExists(at: sharedFile) { return sharedFile }

        let userDir = baseURL.appendingPathComponent("xcuserdata", isDirectory: true).path
        if fs.directoryExists(at: userDir), let users = try? fs.listDirectory(at: userDir) {
            for u in users where u.hasSuffix(".xcuserdatad") {
                let dir = URL(fileURLWithPath: userDir).appendingPathComponent(u).appendingPathComponent("xcschemes", isDirectory: true).path
                let file = URL(fileURLWithPath: dir).appendingPathComponent("\(schemeName).xcscheme").path
                if fs.fileExists(at: file) { return file }
            }
        }
        return nil
    }

    public static func sharedSchemesDirectory(projectPath: String) -> String {
        URL(fileURLWithPath: projectPath).appendingPathComponent("xcshareddata/xcschemes", isDirectory: true).path
    }

    public static func rewriteBuildConfigurations(in schemeXML: String, to configuration: String) throws -> String {
        let re = try NSRegularExpression(pattern: #"buildConfiguration\s*=\s*"[^"]*""#)
        let range = NSRange(location: 0, length: (schemeXML as NSString).length)
        return re.stringByReplacingMatches(in: schemeXML, options: [], range: range, withTemplate: #"buildConfiguration="\#(configuration)""#)
    }
}

