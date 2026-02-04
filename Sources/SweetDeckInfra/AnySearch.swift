import Foundation

public enum SweetDeckAnyJSONSearch {
    public static func findStringArray(_ any: Any, rootKeys: [String], nestedKey: String) -> [String]? {
        guard let root = any as? [String: Any] else { return nil }
        for key in rootKeys {
            if let obj = root[key] as? [String: Any],
               let list = obj[nestedKey] as? [String] {
                return list
            }
        }
        return nil
    }

    public static func findFirstDictionary(_ any: Any, whereKeysExist keys: [String]) -> [String: Any]? {
        if let dict = any as? [String: Any] {
            if keys.contains(where: { dict[$0] != nil }) { return dict }
            for (_, v) in dict {
                if let found = findFirstDictionary(v, whereKeysExist: keys) { return found }
            }
        } else if let array = any as? [Any] {
            for v in array {
                if let found = findFirstDictionary(v, whereKeysExist: keys) { return found }
            }
        }
        return nil
    }

    public static func findFirstInt(_ any: Any, keys: [String]) -> Int? {
        if let dict = any as? [String: Any] {
            for k in keys {
                if let v = dict[k] as? Int { return v }
                if let v = dict[k] as? String, let i = Int(v) { return i }
            }
            for (_, v) in dict {
                if let found = findFirstInt(v, keys: keys) { return found }
            }
        } else if let arr = any as? [Any] {
            for v in arr {
                if let found = findFirstInt(v, keys: keys) { return found }
            }
        }
        return nil
    }
}

