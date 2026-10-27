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

    /// The SwiftData side of the store: one container and its context, on their own executor.
    actor CacheDatabase: ModelActor {
        nonisolated let modelContainer: ModelContainer
        nonisolated let modelExecutor: any ModelExecutor

        init(modelContainer: ModelContainer) {
            self.modelContainer = modelContainer
            modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        }

        func data(for key: String) -> Data? {
            document(key)?.payload
        }

        func store(_ data: Data, for key: String) {
            if let existing = document(key) {
                existing.payload = data
                existing.updatedAt = Date()
            } else {
                modelContext.insert(CachedDocument(key: key, payload: data, updatedAt: Date()))
            }
            try? modelContext.save()
        }

        func remove(_ key: String) {
            guard let existing = document(key) else { return }
            modelContext.delete(existing)
            try? modelContext.save()
        }

        func removeAll() {
            try? modelContext.delete(model: CachedDocument.self)
            try? modelContext.save()
        }

        private func document(_ key: String) -> CachedDocument? {
            var descriptor = FetchDescriptor<CachedDocument>(predicate: #Predicate { $0.key == key })
            descriptor.fetchLimit = 1
            return try? modelContext.fetch(descriptor).first
        }
    }

    /// The on-device `LocalStore` (IS-04):
    /// - it lives in `Library/Caches/WaiveraCache`, which is never in iCloud or Finder backups,
    ///   and the folder is also marked excluded from backup on every launch;
    /// - its files are readable after the first unlock (a push can wake the app while locked)
    ///   and encrypted again from a restart until then;
    /// - sign-out deletes the SQLite files and starts a fresh database, because deleted rows
    ///   stay readable in SQLite free pages until the file is rewritten.
    public actor SwiftDataLocalStore: LocalStore {
        static let folderName = "WaiveraCache"
        static let fileName = "WaiveraCache.store"

        private let fileURL: URL?
        private var database: CacheDatabase?

        private init(fileURL: URL?, database: CacheDatabase) {
            self.fileURL = fileURL
            self.database = database
        }

        /// The app's store; `inMemory` for previews and UI tests.
        public static func make(inMemory: Bool = false) throws -> SwiftDataLocalStore {
            if inMemory {
                return SwiftDataLocalStore(fileURL: nil, database: try openDatabase(at: nil))
            }
            removeLegacyStore()
            let url = try preparedFileURL()
            return SwiftDataLocalStore(fileURL: url, database: try openDatabase(at: url))
        }

        /// The store file under Caches, with the folder excluded from backup and protected.
        static func preparedFileURL() throws -> URL {
            let fileManager = FileManager.default
            let caches = try fileManager.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            var folder = caches.appending(path: folderName, directoryHint: .isDirectory)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            #if os(iOS)
                try fileManager.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: folder.path(percentEncoded: false)
                )
            #endif
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            return folder.appending(path: fileName, directoryHint: .notDirectory)
        }

        static func openDatabase(at url: URL?) throws -> CacheDatabase {
            let schema = Schema([CachedDocument.self])
            let configuration: ModelConfiguration
            if let url {
                configuration = ModelConfiguration("WaiveraCache", schema: schema, url: url, cloudKitDatabase: .none)
            } else {
                configuration = ModelConfiguration("WaiveraCache", schema: schema, isStoredInMemoryOnly: true)
            }
            return CacheDatabase(modelContainer: try ModelContainer(for: schema, configurations: [configuration]))
        }

        /// Builds before IS-04 kept the cache at SwiftData's default place in Application Support,
        /// which is backed up; it is only a cache, so it is deleted rather than moved.
        static func removeLegacyStore() {
            guard
                let support = try? FileManager.default.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: false
                )
            else { return }
            let legacy = support.appending(path: fileName, directoryHint: .notDirectory)
            for file in storeFiles(for: legacy) {
                try? FileManager.default.removeItem(at: file)
            }
        }

        /// The SQLite file and its journal files.
        static func storeFiles(for url: URL) -> [URL] {
            let path = url.path(percentEncoded: false)
            return [url, URL(filePath: path + "-wal"), URL(filePath: path + "-shm")]
        }

        public func data(for key: CacheKey) async -> Data? {
            await database?.data(for: key.rawValue)
        }

        public func store(_ data: Data, for key: CacheKey) async {
            await database?.store(data, for: key.rawValue)
        }

        public func remove(_ key: CacheKey) async {
            await database?.remove(key.rawValue)
        }

        /// Sign-out: rows deleted, then the files themselves, then a new empty database.
        public func removeAll() async {
            await database?.removeAll()
            guard let fileURL else { return }
            // Releasing the only reference closes the container before its files go.
            database = nil
            for file in Self.storeFiles(for: fileURL) {
                try? FileManager.default.removeItem(at: file)
            }
            // If the folder cannot be recreated, the rest of the session caches in memory only.
            database =
                (try? Self.preparedFileURL()).flatMap { try? Self.openDatabase(at: $0) }
                ?? (try? Self.openDatabase(at: nil))
        }
    }
#endif
