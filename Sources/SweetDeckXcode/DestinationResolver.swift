import Foundation
import SweetDeckDomain
import SweetDeckInfra

public struct SweetDeckSimulatorDevice: Codable, Hashable, Sendable {
    public var name: String
    public var udid: String
    public var state: String?
    public var isAvailable: Bool?
    public var runtime: String?
}

public enum SweetDeckDestinationResolver {
    public static func extractSimulatorName(destination: String) -> String? {
        // destination is typically "platform=iOS Simulator,name=iPhone 15"
        for part in destination.split(separator: ",") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, kv[0].trimmingCharacters(in: .whitespacesAndNewlines) == "name" {
                return kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    public static func extractID(destination: String) -> String? {
        for part in destination.split(separator: ",") {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, kv[0].trimmingCharacters(in: .whitespacesAndNewlines) == "id" {
                return kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    public static func looksLikeUUID(_ value: String) -> Bool {
        let regex = try? NSRegularExpression(pattern: "^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")
        let range = NSRange(location: 0, length: value.utf16.count)
        return (regex?.firstMatch(in: value, options: [], range: range) != nil)
    }
}

