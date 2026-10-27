import Foundation
import Testing

@testable import ChatFeature

/// 02 §4b and 10 §8: 30 rows with 12 distinct authors make at most 12 requests, 4 at a time;
/// bot and empty ids make none.
@MainActor
struct AvatarPrefetcherTests {
    @Test("Distinct valid ids are requested once each, never more than four at a time")
    func dedupeAndConcurrency() async {
        let avatars = CountingAvatars()
        let prefetcher = AvatarPrefetcher<Data>(repository: avatars) { $0 }
        let authors = (0..<12).map { "usr_\($0)" }
        let rows = (0..<30).map { authors[$0 % authors.count] }
        await prefetcher.prefetch(rows + ["bot:waivera", "", "  ", "null", "undefined"])
        await prefetcher.prefetch(rows)
        let requests = await avatars.requests
        #expect(requests.count == 12)
        #expect(Set(requests) == Set(authors))
        #expect(await avatars.maxInFlight <= AvatarPrefetcher<Data>.concurrency)
        #expect(await avatars.maxInFlight > 1)
        #expect(prefetcher.images["usr_3"] == Data("usr_3".utf8))
    }

    @Test("An id without an avatar is not asked for again on this screen")
    func missingIsRemembered() async {
        let avatars = CountingAvatars()
        let prefetcher = AvatarPrefetcher<Data>(repository: avatars) { $0 }
        await prefetcher.prefetch(["missing_1"])
        await prefetcher.prefetch(["missing_1"])
        #expect(await avatars.requests == ["missing_1"])
        #expect(prefetcher.images.isEmpty)
    }

    @Test("Invalid ids never reach the repository")
    func invalidIds() {
        #expect(!AvatarPrefetcher<Data>.isValid("bot:123"))
        #expect(!AvatarPrefetcher<Data>.isValid("null"))
        #expect(!AvatarPrefetcher<Data>.isValid(" "))
        #expect(AvatarPrefetcher<Data>.isValid("usr_priya_raman"))
    }
}
