import Foundation

/// JSON settings for every sprout_api call.
public enum WaiveraJSON {
    public static func decoder() -> JSONDecoder {
        JSONDecoder()
    }

    /// Keys are sorted so request bodies are stable in tests and logs.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
