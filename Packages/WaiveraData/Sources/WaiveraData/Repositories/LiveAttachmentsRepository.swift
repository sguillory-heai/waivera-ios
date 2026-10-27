import Foundation
import WaiveraAPI

/// Uploads through the multipart endpoint and downloads with the auth header and one forced
/// refresh on 401, like every other request (01 §4, gap G-15).
public actor LiveAttachmentsRepository: AttachmentsRepository {
    /// In-memory budget for downloaded files.
    static let cacheBudget = 40 * 1_024 * 1_024

    private let api: APIClient
    private var cache: [Int: Data] = [:]
    private var order: [Int] = []
    private var cachedBytes = 0
    private var inFlight: [Int: Task<Data, any Error>] = [:]
    /// Bumped by `clear()`: a download that finishes after sign-out never lands in the cache
    /// the next account reads (IS-08).
    private var generation = 0

    public init(api: APIClient) {
        self.api = api
    }

    public func upload(data: Data, fileName: String, mimeType: String) async throws -> Attachment {
        let response: ChatAttachmentUploadResponse
        do {
            response = try await api.uploadAttachment(MultipartFile(data: data, fileName: fileName, mimeType: mimeType))
        } catch let error as WaiveraError where error.isTransient {
            throw error
        } catch let error as WaiveraError where error == .attachmentBlocked {
            throw error
        } catch {
            throw WaiveraError.attachmentUploadFailed
        }
        let status = response.scanStatus.map(ChatMapper.scanStatus) ?? .clean
        if status == .rejected { throw WaiveraError.attachmentBlocked }
        let name = response.originalName?.nilIfBlank ?? fileName
        let contentType = response.contentType?.nilIfBlank ?? mimeType
        return Attachment(
            url: response.documentUrl,
            kind: Attachment.kind(contentType: contentType, type: nil, name: name),
            name: name,
            contentType: contentType,
            size: response.size ?? Int64(data.count),
            scanStatus: status
        )
    }

    public func data(forMessageId messageId: Int) async throws -> Data {
        if let cached = cache[messageId] {
            touch(messageId)
            return cached
        }
        let current = generation
        if let running = inFlight[messageId] {
            let data = try await running.value
            guard generation == current else { throw WaiveraError.signedOut }
            return data
        }
        let api = api
        let task = Task { try await api.attachmentData(messageId: messageId) }
        inFlight[messageId] = task
        defer { if generation == current { inFlight[messageId] = nil } }
        let data: Data
        do {
            data = try await task.value
        } catch {
            throw WaiveraError.from(error)
        }
        guard generation == current else { throw WaiveraError.signedOut }
        store(data, for: messageId)
        return data
    }

    /// Sign-out: cancels running downloads and drops everything cached.
    public func clear() {
        generation += 1
        cache.removeAll()
        order.removeAll()
        cachedBytes = 0
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
    }

    private func store(_ data: Data, for messageId: Int) {
        guard data.count <= Self.cacheBudget else { return }
        cache[messageId] = data
        order.append(messageId)
        cachedBytes += data.count
        while cachedBytes > Self.cacheBudget, let oldest = order.first {
            order.removeFirst()
            cachedBytes -= cache.removeValue(forKey: oldest)?.count ?? 0
        }
    }

    private func touch(_ messageId: Int) {
        order.removeAll { $0 == messageId }
        order.append(messageId)
    }
}

/// Avatars: memory cache honouring the server's expiry, a negative cache for users without
/// one, and one request per user at a time.
public actor LiveAvatarRepository: AvatarRepository {
    static let negativeLifetime: TimeInterval = 10 * 60
    static let defaultLifetime: TimeInterval = 60 * 60

    private let api: APIClient
    private let clock: any WaiveraClock
    private var cache: [String: (data: Data?, expiresAt: Date)] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private var generation = 0

    public init(api: APIClient, clock: any WaiveraClock) {
        self.api = api
        self.clock = clock
    }

    public func avatar(userId: String) async -> Data? {
        if let entry = cache[userId], entry.expiresAt > clock.now { return entry.data }
        if let running = inFlight[userId] { return await running.value }
        let api = api
        let task = Task { () -> (Data?, TimeInterval) in
            do {
                let result = try await api.avatar(userId: userId)
                let lifetime = result.expiresInSeconds.map(TimeInterval.init) ?? Self.defaultLifetime
                return (result.imageData, result.imageData == nil ? Self.negativeLifetime : lifetime)
            } catch {
                return (nil, Self.negativeLifetime)
            }
        }
        let shared = Task { await task.value.0 }
        inFlight[userId] = shared
        let current = generation
        let (data, lifetime) = await task.value
        // Signed out meanwhile: the picture is not kept for the next account.
        guard generation == current else { return nil }
        inFlight[userId] = nil
        cache[userId] = (data, clock.now.addingTimeInterval(lifetime))
        return data
    }

    public func clear() {
        generation += 1
        cache.removeAll()
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
    }
}
