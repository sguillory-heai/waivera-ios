import Foundation

/// A string-backed enum that never fails to decode: unknown values become `unknownCase`,
/// strings match case-insensitively, and integers (the hub sends enums as numbers, gap G-03)
/// map through `integerCases` in C# declaration order.
public protocol OpenEnum: RawRepresentable, Codable, Hashable, Sendable, CaseIterable where RawValue == String {
    static var unknownCase: Self { get }
    /// C# member order for enums that the hub serialises as integers. Empty when the server
    /// always sends a string.
    static var integerCases: [Self] { get }
}

extension OpenEnum {
    public static var integerCases: [Self] { [] }

    public init(lenient raw: String?) {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            self = Self.unknownCase
            return
        }
        self = Self.allCases.first { $0.rawValue.caseInsensitiveCompare(raw) == .orderedSame } ?? Self.unknownCase
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            let cases = Self.integerCases
            self = cases.indices.contains(number) ? cases[number] : Self.unknownCase
        } else if let raw = try? container.decode(String.self) {
            self.init(lenient: raw)
        } else {
            self = Self.unknownCase
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Decodes a `Bool` from `true`/`false`, `"true"`/`"false"` or `0`/non-zero.
public struct LenientBool: Codable, Hashable, Sendable {
    public var value: Bool

    public init(_ value: Bool) {
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        value = json.boolValue ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// An id the server sometimes sends as a number and sometimes as a string; kept as a string.
public struct LenientID: Codable, Hashable, Sendable {
    public var value: String

    public init(_ value: String) {
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        let json = try JSONValue(from: decoder)
        switch json {
        case .string(let string): value = string
        case .number: value = json.intValue.map(String.init) ?? ""
        default: value = ""
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// An array that drops elements which fail to decode, mirroring the Expo normalisers that
/// skip malformed rows instead of failing the whole list.
public struct LossyArray<Element: Decodable & Sendable>: Decodable, Sendable {
    public var elements: [Element]

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else {
                _ = try? container.decode(JSONValue.self)
            }
        }
        elements = result
    }
}

extension KeyedDecodingContainer {
    /// Absent, `null` and malformed all decode as `nil`, so one bad optional field never
    /// discards a whole payload.
    public func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    public func lenientBool(forKey key: Key, default fallback: Bool = false) -> Bool {
        lenient(LenientBool.self, forKey: key)?.value ?? fallback
    }

    public func lenientInt(forKey key: Key) -> Int? {
        lenient(JSONValue.self, forKey: key)?.intValue
    }

    public func lenientArray<T: Decodable & Sendable>(_ type: T.Type, forKey key: Key) -> [T] {
        lenient(LossyArray<T>.self, forKey: key)?.elements ?? []
    }
}
