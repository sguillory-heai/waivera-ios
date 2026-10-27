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
