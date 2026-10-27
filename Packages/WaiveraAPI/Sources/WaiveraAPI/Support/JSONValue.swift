import Foundation

/// Arbitrary JSON, used for server fields whose shape the client does not own
/// (`messageDoc`, `systemEventData`) and for raw hub arguments before typed decoding.
public enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    public subscript(index: Int) -> JSONValue? {
        guard case .array(let array) = self, array.indices.contains(index) else { return nil }
        return array[index]
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// Integers arrive as JSON numbers; a numeric string is accepted too because some
    /// legacy payloads stringify ids.
    public var intValue: Int? {
        switch self {
        case .number(let value):
            guard value.rounded() == value, abs(value) < 9.0e15 else { return nil }
            return Int(value)
        case .string(let value):
            return Int(value.trimmingCharacters(in: .whitespaces))
        default:
            return nil
        }
    }

    /// Accepts `true`, `"true"` (any casing) and any non-zero number, matching the
    /// tolerance the backend's legacy payloads require.
    public var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            switch value.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Re-decodes this value as `type` with the shared sprout_api decoder.
    public func decode<T: Decodable>(as type: T.Type = T.self) throws -> T {
        let data = try WaiveraJSON.encoder().encode(self)
        return try WaiveraJSON.decoder().decode(type, from: data)
    }

    /// Builds a value from the untyped objects `JSONSerialization` and SignalR produce.
    public init(any value: Any?) {
        guard let value, !(value is NSNull) else {
            self = .null
            return
        }
        if let string = value as? String {
            self = .string(string)
        } else if let number = value as? NSNumber {
            self = JSONValue.fromNumber(number)
        } else if let array = value as? [Any] {
            self = .array(array.map { JSONValue(any: $0) })
        } else if let object = value as? [String: Any] {
            self = .object(object.mapValues { JSONValue(any: $0) })
        } else if let json = value as? JSONValue {
            self = json
        } else {
            self = .null
        }
    }

    private static func fromNumber(_ number: NSNumber) -> JSONValue {
        // Booleans bridge to NSNumber with the ObjC type "c"; plain integers never do.
        if String(cString: number.objCType) == "c" {
            return .bool(number.boolValue)
        }
        return .number(number.doubleValue)
    }
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            if value.rounded() == value, abs(value) < 9.0e15 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
