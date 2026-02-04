import Foundation

public struct SweetDeckError: Error, CustomStringConvertible, Sendable {
    public enum Code: Int, Codable, Sendable {
        case usage = 2
        case config = 10
        case toolNotFound = 20
        case xcodebuildFailed = 30
        case simctlFailed = 40
        case devicectlFailed = 50
        case projectEditFailed = 70
        case unknown = 1
    }

    public var code: Code
    public var message: String
    public var details: [String: String]

    public init(code: Code, message: String, details: [String: String] = [:]) {
        self.code = code
        self.message = message
        self.details = details
    }

    public var description: String {
        if details.isEmpty { return message }
        return "\(message) (\(details.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")))"
    }
}

public struct SweetDeckJSONResponse<T: Encodable>: Encodable {
    public var ok: Bool
    public var code: Int
    public var message: String
    public var details: T?

    public init(ok: Bool, code: Int, message: String, details: T? = nil) {
        self.ok = ok
        self.code = code
        self.message = message
        self.details = details
    }
}
