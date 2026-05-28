import Foundation

public enum MediaSFUBridgeJson {
    public static func encode(_ value: Any?) throws -> String {
        let normalized = normalize(value)
        guard JSONSerialization.isValidJSONObject(normalized) else {
            throw MediaSFUBridgeJsonError.invalidJSONObject
        }

        let data = try JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw MediaSFUBridgeJsonError.invalidUtf8
        }
        return json
    }

    public static func decodeObject(_ json: String) throws -> [String: Any] {
        let data = Data(json.utf8)
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard let object = decoded as? [String: Any] else {
            throw MediaSFUBridgeJsonError.expectedObject
        }
        return object
    }

    public static func decodeArray(_ json: String) throws -> [Any] {
        let data = Data(json.utf8)
        let decoded = try JSONSerialization.jsonObject(with: data)
        guard let array = decoded as? [Any] else {
            throw MediaSFUBridgeJsonError.expectedArray
        }
        return array
    }

    private static func normalize(_ value: Any?) -> Any {
        switch value {
        case nil:
            return NSNull()
        case let null as NSNull:
            return null
        case let dict as [String: Any?]:
            return dict.mapValues { normalize($0) }
        case let dict as [String: Any]:
            return dict.mapValues { normalize($0) }
        case let array as [Any?]:
            return array.map { normalize($0) }
        case let array as [Any]:
            return array.map { normalize($0) }
        case let number as NSNumber:
            return number
        case let string as NSString:
            return string
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case let int as Int:
            return int
        case let double as Double:
            return double
        case let float as Float:
            return float
        default:
            return String(describing: value!)
        }
    }
}

public enum MediaSFUBridgeJsonError: Error {
    case invalidJSONObject
    case invalidUtf8
    case expectedObject
    case expectedArray
}