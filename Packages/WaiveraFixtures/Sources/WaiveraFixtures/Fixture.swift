import Foundation

/// Loads the shared fixture files. Names are the file names without `.json`, for example
/// `Fixture.data("rest-chat-get-all")`. See `FIXTURES.md` for what each one covers.
public enum Fixture {
    public enum LoadError: Error, Equatable {
        case missing(String)
    }

    public static func url(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw LoadError.missing(name)
        }
        return url
    }

    public static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    /// Every fixture name, sorted.
    public static var allNames: [String] {
        guard let directory = Bundle.module.resourceURL?.appendingPathComponent("Fixtures"),
            let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }
        return files.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }
}
