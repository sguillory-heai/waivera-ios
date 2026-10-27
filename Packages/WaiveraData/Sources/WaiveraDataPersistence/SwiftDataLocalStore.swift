#if canImport(SwiftData)
    import Foundation
    import SwiftData
    import WaiveraData

    /// One cached JSON document per `CacheKey`. Documents instead of a normalized schema keep
    /// the cache free of migrations; the server stays the source of truth (ADR 0002).
    @Model
    final class CachedDocument {
        @Attribute(.unique) var key: String
        var payload: Data
        var updatedAt: Date

        init(key: String, payload: Data, updatedAt: Date) {
            self.key = key
            self.payload = payload
            self.updatedAt = updatedAt
        }
    }

    /// The on-device `LocalStore`. Lives in Application Support (not backed up by default
    /// beyond the app container) and is wiped on sign-out.
    public actor SwiftDataLocalStore: LocalStore, ModelActor {
        public nonisolated let modelContainer: ModelContainer
        public nonisolated let modelExecutor: any ModelExecutor

        public init(modelContainer: ModelContainer) {
            self.modelContainer = modelContainer
            modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        }

        /// The app's store; `inMemory` for previews and UI tests.
        public static func make(inMemory: Bool = false) throws -> SwiftDataLocalStore {
            let schema = Schema([CachedDocument.self])
            let configuration = ModelConfiguration("WaiveraCache", schema: schema, isStoredInMemoryOnly: inMemory)
            return SwiftDataLocalStore(modelContainer: try ModelContainer(for: schema, configurations: [configuration]))
        }

        public func data(for key: CacheKey) -> Data? {
            document(key.rawValue)?.payload
        }

        public func store(_ data: Data, for key: CacheKey) {
            if let existing = document(key.rawValue) {
                existing.payload = data
                existing.updatedAt = Date()
            } else {
                modelContext.insert(CachedDocument(key: key.rawValue, payload: data, updatedAt: Date()))
            }
            try? modelContext.save()
        }

        public func remove(_ key: CacheKey) {
            guard let existing = document(key.rawValue) else { return }
            modelContext.delete(existing)
            try? modelContext.save()
        }

        public func removeAll() {
            try? modelContext.delete(model: CachedDocument.self)
            try? modelContext.save()
        }

        private func document(_ key: String) -> CachedDocument? {
            var descriptor = FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key == key })
            descriptor.fetchLimit = 1
            return try? modelContext.fetch(descriptor).first
        }
    }
#endif
