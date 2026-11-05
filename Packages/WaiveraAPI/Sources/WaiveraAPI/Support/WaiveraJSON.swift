import Foundation

/// JSON settings for every sprout_api payload, REST and hub alike.
///
/// - Keys are canonicalised with the same rule as .NET `JsonNamingPolicy.CamelCase`, which is
///   idempotent on camelCase and turns PascalCase into the server's camelCase. That one rule
///   makes hub payloads case-insensitive (gap G-03) and lets PascalCase `ExceptionMiddleware`
///   bodies decode with the same types.
/// - Dates go through `WaiveraInstant`, so zone-less timestamps are UTC.
public enum WaiveraJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { path in
            let last = path.last?.stringValue ?? ""
            return CanonicalKey(stringValue: camelCase(last))
        }
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = WaiveraInstant.parse(raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised timestamp")
            }
            return date
        }
        return decoder
    }

    /// The same JSON with every unpaired UTF-16 surrogate escape (half an emoji, as .NET writes
    /// `\uD83D` when text was cut mid-character) replaced by U+FFFD, or nil when there was none.
    /// Foundation rejects the whole document for one such escape; Android's parser keeps it.
    public static func repairingSurrogates(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var changed = false
        var index = 0
        let replacement = Array(#"\uFFFD"#.utf8)
        while index < bytes.count {
            let byte = bytes[index]
            guard byte == UInt8(ascii: "\\"), index + 1 < bytes.count else {
                out.append(byte)
                index += 1
                continue
            }
            guard bytes[index + 1] == UInt8(ascii: "u"), let unit = hexUnit(bytes, at: index + 2) else {
                // Any other escape, `\\` included, is copied whole so its second byte never starts one.
                out.append(byte)
                out.append(bytes[index + 1])
                index += 2
                continue
            }
            switch unit {
            case 0xD800...0xDBFF:
                if index + 7 < bytes.count, bytes[index + 6] == UInt8(ascii: "\\"),
                    bytes[index + 7] == UInt8(ascii: "u"), let low = hexUnit(bytes, at: index + 8),
                    (0xDC00...0xDFFF).contains(low)
                {
                    out.append(contentsOf: bytes[index..<(index + 12)])
                    index += 12
                } else {
                    out.append(contentsOf: replacement)
                    changed = true
                    index += 6
                }
            case 0xDC00...0xDFFF:
                out.append(contentsOf: replacement)
                changed = true
                index += 6
            default:
                out.append(contentsOf: bytes[index..<(index + 6)])
                index += 6
            }
        }
        return changed ? Data(out) : nil
    }

    private static func hexUnit(_ bytes: [UInt8], at start: Int) -> UInt16? {
        guard start + 4 <= bytes.count else { return nil }
        var value: UInt16 = 0
        for byte in bytes[start..<(start + 4)] {
            let digit: UInt8
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
            default: return nil
            }
            value = value << 4 | UInt16(digit)
        }
        return value
    }

    /// Keys are sorted so request bodies are stable in tests and logs.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(WaiveraInstant.format(date))
        }
        return encoder
    }

    /// Port of `System.Text.Json.JsonNamingPolicy.CamelCase` (`FixCasing`).
    public static func camelCase(_ name: String) -> String {
        var characters = Array(name)
        guard let first = characters.first, first.isUppercase else { return name }
        for index in characters.indices {
            if index == 1, !characters[index].isUppercase { break }
            let hasNext = index + 1 < characters.count
            if index > 0, hasNext, !characters[index + 1].isUppercase {
                if characters[index + 1] == " " {
                    characters[index] = Character(characters[index].lowercased())
                }
                break
            }
            characters[index] = Character(characters[index].lowercased())
        }
        return String(characters)
    }
}

struct CanonicalKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
