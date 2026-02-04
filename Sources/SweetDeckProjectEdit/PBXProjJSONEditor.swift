import Foundation
import SweetDeckDomain
import SweetDeckInfra
import XcodeProj
import PathKit

public final class SweetDeckPBXProjJSONEditor {
    private let process: SweetDeckProcessRunning
    private let console: SweetDeckConsole

    public init(process: SweetDeckProcessRunning, console: SweetDeckConsole) {
        self.process = process
        self.console = console
    }

    public func loadPBXProjJSON(pbxprojPath: String, cwd: String) throws -> [String: Any] {
        let res = try process.runCapture(
            SweetDeckCommand(executable: "/usr/bin/plutil", arguments: ["-convert", "json", "-o", "-", pbxprojPath]),
            cwd: cwd
        )
        guard res.exitCode == 0 else {
            throw SweetDeckError(code: .projectEditFailed, message: "plutil failed to convert pbxproj to json", details: ["exit": "\(res.exitCode)"])
        }
        let any = try SweetDeckJSON.parseAny(from: res.stdout)
        guard let dict = any as? [String: Any] else {
            throw SweetDeckError(code: .projectEditFailed, message: "Unexpected pbxproj json structure")
        }
        return dict
    }

    public func writePBXProjOpenStep(json: [String: Any], pbxprojPath: String, cwd: String) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try SweetDeckTempFiles.withTemporaryFile(prefix: "sweetdeck-pbxproj-", suffix: ".json") { tmp in
            try data.write(to: URL(fileURLWithPath: tmp), options: [.atomic])
            let res = try process.runStreaming(
                SweetDeckCommand(executable: "/usr/bin/plutil", arguments: ["-convert", "openstep", "-o", pbxprojPath, tmp]),
                cwd: cwd,
                streamToStdout: console.outputFormat == .human,
                streamToStderr: console.outputFormat == .human
            )
            guard res.exitCode == 0 else {
                throw SweetDeckError(code: .projectEditFailed, message: "plutil failed to write pbxproj", details: ["exit": "\(res.exitCode)"])
            }
        }
    }

    public func listConfigurations(json: [String: Any]) -> [String] {
        let objects = (json["objects"] as? [String: Any]) ?? [:]
        var names: Set<String> = []
        for (_, v) in objects {
            guard let obj = v as? [String: Any], (obj["isa"] as? String) == "XCBuildConfiguration" else { continue }
            if let name = obj["name"] as? String { names.insert(name) }
        }
        return Array(names).sorted()
    }

    public func duplicateConfiguration(
        json: inout [String: Any],
        newName: String,
        basedOn: String,
        scope: String,
        targetNames: [String]
    ) throws {
        guard var objects = json["objects"] as? [String: Any] else {
            throw SweetDeckError(code: .projectEditFailed, message: "pbxproj json missing objects")
        }
        guard let rootObjectId = json["rootObject"] as? String,
              let rootObj = objects[rootObjectId] as? [String: Any],
              (rootObj["isa"] as? String) == "PBXProject"
        else {
            throw SweetDeckError(code: .projectEditFailed, message: "pbxproj json missing root PBXProject")
        }

        func configurationListIDsForProject() throws -> [String] {
            guard let list = rootObj["buildConfigurationList"] as? String else {
                throw SweetDeckError(code: .projectEditFailed, message: "PBXProject missing buildConfigurationList")
            }
            return [list]
        }

        func configurationListIDsForTargets(names: Set<String>?) throws -> [String] {
            guard let targetIds = rootObj["targets"] as? [String] else { return [] }
            var listIDs: [String] = []
            for tid in targetIds {
                guard let t = objects[tid] as? [String: Any] else { continue }
                if let names, let tname = t["name"] as? String, !names.contains(tname) { continue }
                if let list = t["buildConfigurationList"] as? String {
                    listIDs.append(list)
                }
            }
            return listIDs
        }

        let listIDs: [String]
        switch scope {
        case "project":
            listIDs = try configurationListIDsForProject()
        case "all-targets":
            listIDs = try configurationListIDsForTargets(names: nil)
        case "target":
            guard !targetNames.isEmpty else {
                throw SweetDeckError(code: .usage, message: "--target is required when scope=target")
            }
            listIDs = try configurationListIDsForTargets(names: Set(targetNames))
        default:
            throw SweetDeckError(code: .usage, message: "Invalid scope", details: ["scope": scope])
        }

        func nextID() -> String {
            let hex = UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased()
            return String(hex.prefix(24))
        }

        for listId in listIDs {
            guard var listObj = objects[listId] as? [String: Any],
                  (listObj["isa"] as? String) == "XCConfigurationList",
                  var buildConfigs = listObj["buildConfigurations"] as? [String]
            else {
                throw SweetDeckError(code: .projectEditFailed, message: "XCConfigurationList not found", details: ["id": listId])
            }

            let baseId = buildConfigs.first { id in
                guard let cfg = objects[id] as? [String: Any], (cfg["isa"] as? String) == "XCBuildConfiguration" else { return false }
                return (cfg["name"] as? String) == basedOn
            }
            guard let baseId else {
                throw SweetDeckError(code: .projectEditFailed, message: "Base configuration not found in scope", details: ["basedOn": basedOn])
            }

            if buildConfigs.contains(where: { id in
                guard let cfg = objects[id] as? [String: Any], (cfg["isa"] as? String) == "XCBuildConfiguration" else { return false }
                return (cfg["name"] as? String) == newName
            }) {
                throw SweetDeckError(code: .projectEditFailed, message: "Configuration already exists in scope", details: ["name": newName])
            }

            guard var newObj = objects[baseId] as? [String: Any] else {
                throw SweetDeckError(code: .projectEditFailed, message: "Failed to read base configuration object")
            }
            newObj["name"] = newName
            let newId = nextID()
            objects[newId] = newObj
            buildConfigs.append(newId)
            listObj["buildConfigurations"] = buildConfigs
            objects[listId] = listObj
        }

        json["objects"] = objects
    }

    public func listPackages(json: [String: Any]) -> [[String: Any]] {
        let objects = (json["objects"] as? [String: Any]) ?? [:]
        var results: [[String: Any]] = []
        for (id, v) in objects {
            guard let obj = v as? [String: Any], (obj["isa"] as? String) == "XCRemoteSwiftPackageReference" else { continue }
            var item: [String: Any] = ["id": id]
            if let url = obj["repositoryURL"] as? String { item["repositoryURL"] = url }
            if let req = obj["requirement"] as? [String: Any] { item["requirement"] = req }
            results.append(item)
        }
        return results.sorted { ($0["repositoryURL"] as? String ?? "") < ($1["repositoryURL"] as? String ?? "") }
    }

    public func addPackage(
        pbxprojPath: String,
        url: String,
        requirement: SweetDeckPackageRequirement,
        linkProduct: String?,
        targets: [String],
        cwd: String
    ) throws {
        // For correctness, we rely on XcodeProj's public PBXProject.addSwiftPackage implementation.
        // This avoids having to manually create build files and product dependencies.
        try addPackageViaXcodeProj(pbxprojPath: pbxprojPath, url: url, requirement: requirement, linkProduct: linkProduct, targets: targets)
    }

    public func removePackage(
        json: inout [String: Any],
        url: String?,
        identity: String?
    ) throws {
        guard var objects = json["objects"] as? [String: Any] else {
            throw SweetDeckError(code: .projectEditFailed, message: "pbxproj json missing objects")
        }
        guard let rootObjectId = json["rootObject"] as? String,
              var rootObj = objects[rootObjectId] as? [String: Any],
              (rootObj["isa"] as? String) == "PBXProject"
        else {
            throw SweetDeckError(code: .projectEditFailed, message: "pbxproj json missing root PBXProject")
        }

        let matcher: (String) -> Bool
        if let url { matcher = { $0 == url } }
        else if let identity { matcher = { $0.localizedCaseInsensitiveContains(identity) } }
        else { throw SweetDeckError(code: .usage, message: "Provide --url or --identity") }

        let packageIds = objects.compactMap { (id, v) -> String? in
            guard let obj = v as? [String: Any], (obj["isa"] as? String) == "XCRemoteSwiftPackageReference" else { return nil }
            guard let repo = obj["repositoryURL"] as? String, matcher(repo) else { return nil }
            return id
        }
        guard !packageIds.isEmpty else {
            throw SweetDeckError(code: .projectEditFailed, message: "Package not found")
        }

        // Remove from PBXProject.packageReferences
        if var refs = rootObj["packageReferences"] as? [String] {
            refs.removeAll { packageIds.contains($0) }
            rootObj["packageReferences"] = refs
            objects[rootObjectId] = rootObj
        }

        // Remove product dependencies referencing removed packages
        let productDepIds = objects.compactMap { (id, v) -> String? in
            guard let obj = v as? [String: Any], (obj["isa"] as? String) == "XCSwiftPackageProductDependency" else { return nil }
            guard let pkg = obj["package"] as? String, packageIds.contains(pkg) else { return nil }
            return id
        }

        // Remove from targets
        for (id, v) in objects {
            guard var obj = v as? [String: Any], (obj["isa"] as? String)?.hasPrefix("PBX") == true else { continue }
            if var deps = obj["packageProductDependencies"] as? [String] {
                deps.removeAll { productDepIds.contains($0) }
                obj["packageProductDependencies"] = deps
                objects[id] = obj
            }
        }

        // Remove build files referencing product deps and unlink from frameworks phases
        let buildFileIds = objects.compactMap { (id, v) -> String? in
            guard let obj = v as? [String: Any], (obj["isa"] as? String) == "PBXBuildFile" else { return nil }
            guard let productRef = obj["productRef"] as? String, productDepIds.contains(productRef) else { return nil }
            return id
        }

        for (id, v) in objects {
            guard var obj = v as? [String: Any], (obj["isa"] as? String) == "PBXFrameworksBuildPhase" else { continue }
            if var files = obj["files"] as? [String] {
                files.removeAll { buildFileIds.contains($0) }
                obj["files"] = files
                objects[id] = obj
            }
        }

        // Remove objects
        for id in buildFileIds { objects.removeValue(forKey: id) }
        for id in productDepIds { objects.removeValue(forKey: id) }
        for id in packageIds { objects.removeValue(forKey: id) }

        json["objects"] = objects
    }

    public func linkProduct(json: inout [String: Any], product: String, targetName: String) throws {
        guard var objects = json["objects"] as? [String: Any] else {
            throw SweetDeckError(code: .projectEditFailed, message: "pbxproj json missing objects")
        }
        guard let rootObjectId = json["rootObject"] as? String,
              let rootObj = objects[rootObjectId] as? [String: Any],
              let targetIds = rootObj["targets"] as? [String]
        else {
            throw SweetDeckError(code: .projectEditFailed, message: "pbxproj json missing targets")
        }

        let targetId = targetIds.first { tid in
            guard let t = objects[tid] as? [String: Any] else { return false }
            return (t["name"] as? String) == targetName
        }
        guard let targetId, var targetObj = objects[targetId] as? [String: Any] else {
            throw SweetDeckError(code: .projectEditFailed, message: "Target not found", details: ["target": targetName])
        }

        let productDepId = objects.compactMap { (id, v) -> String? in
            guard let obj = v as? [String: Any], (obj["isa"] as? String) == "XCSwiftPackageProductDependency" else { return nil }
            return (obj["productName"] as? String) == product ? id : nil
        }.first
        guard let productDepId else {
            throw SweetDeckError(code: .projectEditFailed, message: "Product dependency not found (add package first)", details: ["product": product])
        }

        var deps = (targetObj["packageProductDependencies"] as? [String]) ?? []
        if !deps.contains(productDepId) {
            deps.append(productDepId)
            targetObj["packageProductDependencies"] = deps
        }

        // Add a PBXBuildFile(productRef=productDepId) and append it to PBXFrameworksBuildPhase.files
        guard let buildPhaseIds = targetObj["buildPhases"] as? [String] else {
            throw SweetDeckError(code: .projectEditFailed, message: "Target missing buildPhases")
        }
        let frameworksPhaseId = buildPhaseIds.first { bid in
            guard let phase = objects[bid] as? [String: Any] else { return false }
            return (phase["isa"] as? String) == "PBXFrameworksBuildPhase"
        }
        guard let frameworksPhaseId, var phaseObj = objects[frameworksPhaseId] as? [String: Any] else {
            throw SweetDeckError(code: .projectEditFailed, message: "Frameworks build phase not found", details: ["target": targetName])
        }

        func nextID() -> String {
            let hex = UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased()
            return String(hex.prefix(24))
        }
        let buildFileId = nextID()
        objects[buildFileId] = [
            "isa": "PBXBuildFile",
            "productRef": productDepId,
        ]
        var files = (phaseObj["files"] as? [String]) ?? []
        files.append(buildFileId)
        phaseObj["files"] = files
        objects[frameworksPhaseId] = phaseObj
        objects[targetId] = targetObj

        json["objects"] = objects
    }

    public func unlinkProduct(json: inout [String: Any], product: String, targetName: String) throws {
        guard var objects = json["objects"] as? [String: Any] else {
            throw SweetDeckError(code: .projectEditFailed, message: "pbxproj json missing objects")
        }
        guard let rootObjectId = json["rootObject"] as? String,
              let rootObj = objects[rootObjectId] as? [String: Any],
              let targetIds = rootObj["targets"] as? [String]
        else {
            throw SweetDeckError(code: .projectEditFailed, message: "pbxproj json missing targets")
        }

        let targetId = targetIds.first { tid in
            guard let t = objects[tid] as? [String: Any] else { return false }
            return (t["name"] as? String) == targetName
        }
        guard let targetId, var targetObj = objects[targetId] as? [String: Any] else {
            throw SweetDeckError(code: .projectEditFailed, message: "Target not found", details: ["target": targetName])
        }

        let productDepId = objects.compactMap { (id, v) -> String? in
            guard let obj = v as? [String: Any], (obj["isa"] as? String) == "XCSwiftPackageProductDependency" else { return nil }
            return (obj["productName"] as? String) == product ? id : nil
        }.first
        guard let productDepId else { return }

        if var deps = targetObj["packageProductDependencies"] as? [String] {
            deps.removeAll { $0 == productDepId }
            targetObj["packageProductDependencies"] = deps
        }

        // Remove PBXBuildFile with productRef == productDepId and unlink from frameworks build phase
        let buildFileIds = objects.compactMap { (id, v) -> String? in
            guard let obj = v as? [String: Any], (obj["isa"] as? String) == "PBXBuildFile" else { return nil }
            return (obj["productRef"] as? String) == productDepId ? id : nil
        }
        if let buildPhaseIds = targetObj["buildPhases"] as? [String] {
            for bid in buildPhaseIds {
                guard var phase = objects[bid] as? [String: Any], (phase["isa"] as? String) == "PBXFrameworksBuildPhase" else { continue }
                if var files = phase["files"] as? [String] {
                    files.removeAll { buildFileIds.contains($0) }
                    phase["files"] = files
                    objects[bid] = phase
                }
            }
        }
        for id in buildFileIds { objects.removeValue(forKey: id) }

        objects[targetId] = targetObj
        json["objects"] = objects
    }

    // MARK: - XcodeProj-backed add (public API)

    private func addPackageViaXcodeProj(
        pbxprojPath: String,
        url: String,
        requirement: SweetDeckPackageRequirement,
        linkProduct: String?,
        targets: [String]
    ) throws {
        // pbxprojPath is inside <project>.xcodeproj/project.pbxproj; XcodeProj operates at .xcodeproj directory level.
        let xcodeprojDir = URL(fileURLWithPath: pbxprojPath).deletingLastPathComponent().path
        let xproj = try XcodeProj(pathString: xcodeprojDir)
        guard let project = xproj.pbxproj.rootObject else {
            throw SweetDeckError(code: .projectEditFailed, message: "No PBXProject root object found")
        }

        guard let product = linkProduct, !product.isEmpty else {
            throw SweetDeckError(code: .usage, message: "--link-product is required in v1 (so we can link the package correctly).")
        }

        let versionReq: XCRemoteSwiftPackageReference.VersionRequirement
        switch requirement {
        case .from(let v): versionReq = .upToNextMajorVersion(v)
        case .exact(let v): versionReq = .exact(v)
        case .branch(let b): versionReq = .branch(b)
        case .revision(let r): versionReq = .revision(r)
        }

        let targetNames: [String]
        if targets.isEmpty {
            targetNames = project.targets.map(\.name)
        } else {
            targetNames = targets
        }

        for target in targetNames {
            _ = try project.addSwiftPackage(repositoryURL: url, productName: product, versionRequirement: versionReq, targetName: target)
        }

        try xproj.write(path: xproj.path ?? Path(xcodeprojDir))
    }
}
