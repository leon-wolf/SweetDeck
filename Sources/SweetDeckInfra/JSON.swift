import Foundation

public enum SweetDeckJSON {
    public static func encodePretty<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: data)
    }

    public static func parseAny(from data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}

