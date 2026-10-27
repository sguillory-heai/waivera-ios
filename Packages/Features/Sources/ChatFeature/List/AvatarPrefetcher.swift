import Foundation
import Observation
import WaiveraData

/// Decoded avatars for the rows on screen (02 §4b, 10 §5). Each id is requested once per
/// screen, at most `concurrency` at a time; `AvatarRepository` owns the TTL and the negative
/// cache. Decoded images stay in `images`, so a row scrolled back into view renders its photo
/// on the first frame with no placeholder flash.
@MainActor
@Observable
final class AvatarPrefetcher<Decoded: Sendable> {
    static var concurrency: Int { 4 }

    private(set) var images: [String: Decoded] = [:]

    @ObservationIgnored private let repository: any AvatarRepository
    @ObservationIgnored private let decode: @Sendable (Data) -> Decoded?
    @ObservationIgnored private var requested: Set<String> = []

    init(repository: any AvatarRepository, decode: @escaping @Sendable (Data) -> Decoded?) {
        self.repository = repository
        self.decode = decode
    }

    /// `bot:` ids, empty ids and the literal `null`/`undefined` never reach the network.
    nonisolated static func isValid(_ userId: String) -> Bool {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("bot:") && trimmed != "null" && trimmed != "undefined"
    }

    /// Loads every id not requested before. Returns when they have all finished.
    func prefetch(_ userIds: [String]) async {
        var fresh: [String] = []
        for id in userIds where Self.isValid(id) && !requested.contains(id) {
            requested.insert(id)
            fresh.append(id)
        }
        guard !fresh.isEmpty else { return }
        let repository = repository
        let decode = decode
        var queue = fresh[...]
        await withTaskGroup(of: (String, Decoded?).self) { group in
            var running = 0
            while running < Self.concurrency, let id = queue.popFirst() {
                group.addTask { await Self.load(id, repository: repository, decode: decode) }
                running += 1
            }
            for await (id, image) in group {
                if let image {
                    images[id] = image
                } else if Task.isCancelled {
                    // Not answered: let the next appearance ask again.
                    requested.remove(id)
                }
                if !Task.isCancelled, let next = queue.popFirst() {
                    group.addTask { await Self.load(next, repository: repository, decode: decode) }
                }
            }
        }
        for id in queue { requested.remove(id) }
    }

    private nonisolated static func load(
        _ id: String,
        repository: any AvatarRepository,
        decode: @Sendable (Data) -> Decoded?
    ) async -> (String, Decoded?) {
        let data = await repository.avatar(userId: id)
        return (id, data.flatMap(decode))
    }
}
