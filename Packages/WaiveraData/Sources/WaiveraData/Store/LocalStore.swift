import Foundation
import WaiveraAPI

/// Names of cached documents. Everything here is user data and is wiped on sign-out.
public struct CacheKey: Hashable, Sendable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let conversations = CacheKey(rawValue: "chat.conversations")
    public static let outbox = CacheKey(rawValue: "chat.outbox")
    public static let activity = CacheKey(rawValue: "chat.activity")
    public static let directory = CacheKey(rawValue: "people.directory")
    public static let milestones = CacheKey(rawValue: "calendar.milestones")
    public static let profile = CacheKey(rawValue: "profile.own")
    /// The last successful bootstrap, for an offline cold start (IF-10).
    public static let bootstrap = CacheKey(rawValue: "session.bootstrap")

    public static func messages(_ conversationId: Int) -> CacheKey {
        CacheKey(rawValue: "chat.messages.\(conversationId)")
    }

    public static func calendar(_ interval: DateInterval) -> CacheKey {
        let start = Int(interval.start.timeIntervalSince1970)
        let end = Int(interval.end.timeIntervalSince1970)
        return CacheKey(rawValue: "calendar.feed.\(start)-\(end)")
    }
}

/// The offline cache screens render from first (ADR 0002). The server stays authoritative:
/// every cached document is replaced by the next successful fetch. Values are stored as
/// JSON documents so the schema never needs a migration; a document that fails to decode
/// after an app update is treated as a miss.
public protocol LocalStore: Sendable {
    func data(for key: CacheKey) async -> Data?
    func store(_ data: Data, for key: CacheKey) async
    func remove(_ key: CacheKey) async
    /// Sign-out.
    func removeAll() async
}

extension LocalStore {
    public func load<T: Decodable>(_ type: T.Type, for key: CacheKey) async -> T? {
        guard let data = await data(for: key) else { return nil }
        return try? WaiveraJSON.decoder().decode(type, from: data)
    }

    public func save<T: Encodable & Sendable>(_ value: T, for key: CacheKey) async {
        guard let data = try? WaiveraJSON.encoder().encode(value) else { return }
        await store(data, for: key)
    }
}

/// Tests, previews and the fake server.
public actor InMemoryLocalStore: LocalStore {
    private var documents: [CacheKey: Data] = [:]

    public init() {}

    public func data(for key: CacheKey) -> Data? { documents[key] }
    public func store(_ data: Data, for key: CacheKey) { documents[key] = data }
    public func remove(_ key: CacheKey) { documents[key] = nil }
    public func removeAll() { documents.removeAll() }

    public var keys: Set<CacheKey> { Set(documents.keys) }
}
