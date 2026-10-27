import Foundation
import WaiveraAPI
import WaiveraData

/// The activity feed behind Today and the Activity screen: the latest feed, the chips and
/// search, paging, and optimistic reads with a toast and Retry when one fails.
///
/// Pages load on demand near the end of the list, and on their own while the oldest loaded
/// page still holds unread items, so the unread count covers more than the first page
/// (11-pitfalls #26). The API has no unread total, so automatic loading stops after
/// `maxAutoPages` and the count is then shown as a lower bound.
@MainActor
final class ActivityController {
    /// Up to 150 more activities (5 pages of 30) load without the person scrolling.
    static let maxAutoPages = 5

    private(set) var resource = Resource<ActivityFeed>()
    private(set) var local = ActivityLocalState()
    /// Called after every change, so the owning model rebuilds its state.
    var onChange: () -> Void = {}

    private let repository: any ActivityRepository
    private let feedback: TodayFeedback
    private let tasks: TaskBag
    private var autoPages = 0

    init(repository: any ActivityRepository, feedback: TodayFeedback, tasks: TaskBag) {
        self.repository = repository
        self.feedback = feedback
        self.tasks = tasks
    }

    /// Follows the feed until the calling task is cancelled.
    func observe() async {
        for await value in repository.feed() {
            resource = value
            onChange()
            autoPageIfNeeded()
        }
    }

    /// Refreshes page 1. Returns false when the request failed.
    @discardableResult
    func refresh() async -> Bool {
        // Page 1 is fetched again, so the automatic budget starts over. Reset before the request:
        // the feed stream can start an automatic page before this method resumes.
        autoPages = 0
        await repository.refresh()
        let value = await latest(repository.feed()) ?? resource
        resource = value
        let succeeded = value.error == nil
        if succeeded {
            local.loadMoreFailed = false
            local.autoPagingCapped = false
        }
        onChange()
        autoPageIfNeeded()
        return succeeded
    }

    /// The age of the last real sync, for refresh-on-open.
    var updatedAt: Date? { resource.updatedAt }

    // MARK: Chips and search

    func setFilter(_ filter: ActivityFilter) {
        guard local.filter != filter else { return }
        local.filter = filter
        onChange()
    }

    func toggleUnreadOnly() {
        local.unreadOnly.toggle()
        onChange()
    }

    func setQuery(_ query: String) {
        guard local.query != query else { return }
        local.query = query
        onChange()
    }

    func clearFilters() {
        local.filter = .all
        local.unreadOnly = false
        local.query = ""
        onChange()
    }

    // MARK: Paging

    /// The list neared its end.
    func loadMoreIfPossible() {
        guard let feed = resource.value, feed.hasMore, resource.updatedAt != nil, !feed.isLoadingMore,
            !local.isLoadingMore, !local.loadMoreFailed
        else { return }
        loadMore(auto: false)
    }

    /// The footer's Retry: loads the next page, or refreshes when the feed itself failed.
    func retryMore() {
        local.loadMoreFailed = false
        onChange()
        if resource.error != nil {
            tasks.run { [weak self] in await self?.refresh() }
        } else {
            loadMore(auto: false)
        }
    }

    private func loadMore(auto: Bool) {
        guard !local.isLoadingMore else { return }
        if auto { autoPages += 1 }
        local.isLoadingMore = true
        local.loadMoreFailed = false
        onChange()
        tasks.run { [weak self] in
            guard let self else { return }
            await repository.loadMore()
            let value = await latest(repository.feed()) ?? resource
            resource = value
            local.isLoadingMore = false
            local.loadMoreFailed = value.error != nil || value.value?.loadMoreError != nil
            onChange()
            autoPageIfNeeded()
        }
    }

    private func autoPageIfNeeded() {
        // Only page past a real sync; a cold cache's has-more flag means nothing yet.
        guard resource.updatedAt != nil, let feed = resource.value, resource.error == nil else { return }
        let merged = ActivityRules.merge(feed.items)
        let mayHoldUnread = ActivityRules.olderPagesMayHoldUnread(merged, hasMore: feed.hasMore, isRead: local.isRead)
        if !mayHoldUnread {
            if local.autoPagingCapped {
                local.autoPagingCapped = false
                onChange()
            }
        } else if autoPages >= Self.maxAutoPages {
            if !local.autoPagingCapped {
                local.autoPagingCapped = true
                onChange()
            }
        } else if !local.loadMoreFailed, !local.isLoadingMore, !feed.isLoadingMore {
            loadMore(auto: true)
        }
    }

    // MARK: Reads

    /// Marks an activity read at once; the request runs behind it and a failure puts the row
    /// back to unread with a Retry toast.
    func markRead(_ activityId: Int64) {
        guard let item = resource.value?.items.first(where: { $0.id == activityId }), !local.isRead(item) else {
            return
        }
        local.readingIds.insert(activityId)
        onChange()
        tasks.run { [weak self] in
            guard let self else { return }
            do {
                try await repository.markRead(activityId: activityId)
            } catch {
                feedback.fail(.markReadFailed(activityId: activityId))
            }
            // Take the repository's settled value before dropping the overlay, so the row never flickers.
            resource = await latest(repository.feed()) ?? resource
            local.readingIds.remove(activityId)
            onChange()
        }
    }

    func markAllRead() {
        guard !local.isMarkingAllRead,
            resource.value?.items.contains(where: { !local.isRead($0) }) == true
        else { return }
        local.isMarkingAllRead = true
        onChange()
        tasks.run { [weak self] in
            guard let self else { return }
            do {
                try await repository.markAllRead()
                feedback.succeed()
            } catch {
                feedback.fail(.markAllFailed)
            }
            resource = await latest(repository.feed()) ?? resource
            local.isMarkingAllRead = false
            onChange()
        }
    }
}
