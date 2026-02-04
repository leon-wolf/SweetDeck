import Foundation

public enum SweetDeckPackageRequirement: Sendable, Hashable {
    case from(String)
    case exact(String)
    case branch(String)
    case revision(String)
}

public protocol SweetDeckProjectEditing {
    func listSchemes(context: SweetDeckResolvedContext, cwd: String) throws -> [String]
    func listConfigurations(context: SweetDeckResolvedContext, cwd: String) throws -> [String]
    func createConfiguration(context: SweetDeckResolvedContext, newName: String, basedOn: String, scope: String, targets: [String], cwd: String) throws
    func createScheme(context: SweetDeckResolvedContext, newName: String, basedOn: String, configuration: String?, shared: Bool, cwd: String) throws
    func listPackages(context: SweetDeckResolvedContext, cwd: String) throws -> Any
    func addPackage(context: SweetDeckResolvedContext, url: String, requirement: SweetDeckPackageRequirement, linkProduct: String?, targets: [String], cwd: String) throws
    func removePackage(context: SweetDeckResolvedContext, url: String?, identity: String?, cwd: String) throws
    func linkProduct(context: SweetDeckResolvedContext, product: String, target: String, cwd: String) throws
    func unlinkProduct(context: SweetDeckResolvedContext, product: String, target: String, cwd: String) throws
}
