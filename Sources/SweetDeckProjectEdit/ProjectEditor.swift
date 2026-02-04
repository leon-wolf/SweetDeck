import Foundation
import SweetDeckDomain
import SweetDeckInfra
import SweetDeckXcode

public final class SweetDeckProjectEditor: SweetDeckProjectEditing {
    private let fs: SweetDeckFileSysteming
    private let console: SweetDeckConsole
    private let process: SweetDeckProcessRunning
    private let xcodebuild: SweetDeckXcodeBuilding
    private let pbx: SweetDeckPBXProjJSONEditor

    public init(fs: SweetDeckFileSysteming, console: SweetDeckConsole, process: SweetDeckProcessRunning, xcodebuild: SweetDeckXcodeBuilding) {
        self.fs = fs
        self.console = console
        self.process = process
        self.xcodebuild = xcodebuild
        self.pbx = SweetDeckPBXProjJSONEditor(process: process, console: console)
    }

    public func listSchemes(context: SweetDeckResolvedContext, cwd: String) throws -> [String] {
        try xcodebuild.list(project: context.project, cwd: cwd).schemes
    }

    public func listConfigurations(context: SweetDeckResolvedContext, cwd: String) throws -> [String] {
        let pbxprojPath = try resolvePBXProjPath(context: context, cwd: cwd)
        let json = try pbx.loadPBXProjJSON(pbxprojPath: pbxprojPath, cwd: cwd)
        return pbx.listConfigurations(json: json)
    }

    public func createConfiguration(context: SweetDeckResolvedContext, newName: String, basedOn: String, scope: String, targets: [String], cwd: String) throws {
        let pbxprojPath = try resolvePBXProjPath(context: context, cwd: cwd)
        var json = try pbx.loadPBXProjJSON(pbxprojPath: pbxprojPath, cwd: cwd)
        try pbx.duplicateConfiguration(json: &json, newName: newName, basedOn: basedOn, scope: scope, targetNames: targets)
        try pbx.writePBXProjOpenStep(json: json, pbxprojPath: pbxprojPath, cwd: cwd)
        console.info("Created configuration \(newName)")
    }

    public func createScheme(context: SweetDeckResolvedContext, newName: String, basedOn: String, configuration: String?, shared: Bool, cwd: String) throws {
        let projectPath = fs.absolutePath(context.project.path, relativeTo: cwd)
        let type = context.project.type ?? (projectPath.hasSuffix(".xcworkspace") ? .xcworkspace : .xcodeproj)
        guard let basedPath = SweetDeckSchemeEditor.findSchemeFile(fs: fs, projectPath: projectPath, projectType: type, schemeName: basedOn) else {
            throw SweetDeckError(code: .projectEditFailed, message: "Base scheme not found", details: ["scheme": basedOn])
        }
        let xml = try String(contentsOfFile: basedPath, encoding: .utf8)
        let targetConfig = configuration ?? context.configuration
        let rewritten = try SweetDeckSchemeEditor.rewriteBuildConfigurations(in: xml, to: targetConfig)

        guard shared else {
            throw SweetDeckError(code: .projectEditFailed, message: "Non-shared schemes are not supported in v1 (use --shared).")
        }
        let destDir = SweetDeckSchemeEditor.sharedSchemesDirectory(projectPath: projectPath)
        try fs.createDirectory(at: destDir)
        let dest = URL(fileURLWithPath: destDir).appendingPathComponent("\(newName).xcscheme").path
        try fs.writeAtomic(data: rewritten.data(using: .utf8)!, to: dest)
        console.info("Created scheme \(newName)")
    }

    public func listPackages(context: SweetDeckResolvedContext, cwd: String) throws -> Any {
        let pbxprojPath = try resolvePBXProjPath(context: context, cwd: cwd)
        let json = try pbx.loadPBXProjJSON(pbxprojPath: pbxprojPath, cwd: cwd)
        return pbx.listPackages(json: json)
    }

    public func addPackage(context: SweetDeckResolvedContext, url: String, requirement: SweetDeckPackageRequirement, linkProduct: String?, targets: [String], cwd: String) throws {
        let pbxprojPath = try resolvePBXProjPath(context: context, cwd: cwd)
        try pbx.addPackage(pbxprojPath: pbxprojPath, url: url, requirement: requirement, linkProduct: linkProduct, targets: targets, cwd: cwd)
        _ = try xcodebuild.resolvePackageDependencies(project: context.project, cwd: cwd)
        console.info("Added package \(url)")
    }

    public func removePackage(context: SweetDeckResolvedContext, url: String?, identity: String?, cwd: String) throws {
        let pbxprojPath = try resolvePBXProjPath(context: context, cwd: cwd)
        var json = try pbx.loadPBXProjJSON(pbxprojPath: pbxprojPath, cwd: cwd)
        try pbx.removePackage(json: &json, url: url, identity: identity)
        try pbx.writePBXProjOpenStep(json: json, pbxprojPath: pbxprojPath, cwd: cwd)
        _ = try xcodebuild.resolvePackageDependencies(project: context.project, cwd: cwd)
        console.info("Removed package")
    }

    public func linkProduct(context: SweetDeckResolvedContext, product: String, target: String, cwd: String) throws {
        let pbxprojPath = try resolvePBXProjPath(context: context, cwd: cwd)
        var json = try pbx.loadPBXProjJSON(pbxprojPath: pbxprojPath, cwd: cwd)
        try pbx.linkProduct(json: &json, product: product, targetName: target)
        try pbx.writePBXProjOpenStep(json: json, pbxprojPath: pbxprojPath, cwd: cwd)
        _ = try xcodebuild.resolvePackageDependencies(project: context.project, cwd: cwd)
        console.info("Linked product \(product) to \(target)")
    }

    public func unlinkProduct(context: SweetDeckResolvedContext, product: String, target: String, cwd: String) throws {
        let pbxprojPath = try resolvePBXProjPath(context: context, cwd: cwd)
        var json = try pbx.loadPBXProjJSON(pbxprojPath: pbxprojPath, cwd: cwd)
        try pbx.unlinkProduct(json: &json, product: product, targetName: target)
        try pbx.writePBXProjOpenStep(json: json, pbxprojPath: pbxprojPath, cwd: cwd)
        _ = try xcodebuild.resolvePackageDependencies(project: context.project, cwd: cwd)
        console.info("Unlinked product \(product) from \(target)")
    }

    private func resolvePBXProjPath(context: SweetDeckResolvedContext, cwd: String) throws -> String {
        let xcodeprojDir = try SweetDeckWorkspaceResolver.resolveEditableXcodeprojPath(fs: fs, project: context.project, cwd: cwd)
        let pbxprojPath = URL(fileURLWithPath: xcodeprojDir).appendingPathComponent("project.pbxproj").path
        guard fs.fileExists(at: pbxprojPath) else {
            throw SweetDeckError(code: .projectEditFailed, message: "project.pbxproj not found", details: ["path": pbxprojPath])
        }
        return pbxprojPath
    }
}

