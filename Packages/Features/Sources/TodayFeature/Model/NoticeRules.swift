import Foundation
import WaiveraAPI
import WaiveraData

/// The chips above the inbox. Approvals include signature requests: both wait on the person's yes.
enum NoticeFilter: String, CaseIterable, Hashable, Sendable {
    case all, tasks, approvals, meetings
}

/// Where a notification opens: an event or a task in the app, Requests, a page of the web app,
/// or nowhere it can reach.
public enum NoticeDestination: Hashable, Sendable {
    case event(id: String)
    /// A task by its friendly number, which the shell looks up before it opens; `web` is its
    /// page, opened instead when the lookup fails.
    case task(number: Int, web: URL?)
    case requests
    case web(URL)
    case none
}

/// One inbox row, with its time already in the employee's zone.
struct NoticeRow: Hashable, Sendable, Identifiable {
    var id: String
    var kind: NoticeKind
    var title: String
    var message: String
    var at: PastLabel?
    var isUnread: Bool
    /// Opens in the browser (no screen for it in the app), so the row shows the open-outside mark.
    var opensOutside: Bool
}

/// The day headings, newest first.
enum NoticeDay: Int, Comparable, Hashable, Sendable {
    case today, yesterday, thisWeek, earlier

    static func < (lhs: NoticeDay, rhs: NoticeDay) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct NoticeGroup: Hashable, Sendable, Identifiable {
    var day: NoticeDay
    var rows: [NoticeRow]
    var id: NoticeDay { day }
}

/// Turns notifications into links. Web pages hang off the configured web base, and only its own
/// host is ever opened, so a notification can never send the person to another site.
struct NoticeLinks: Sendable {
    let webBase: URL?

    func destination(_ notice: Notice) -> NoticeDestination {
        if let eventId = notice.eventId { return .event(id: eventId) }
        if notice.opensRequests { return .requests }
        let key = notice.taskKey
        let path = notice.webPath
        let taskPage = key.map { "/task/\($0)" }
        // Only the task's own page; deeper web pages about it (files, history) stay on the web.
        if let key, let number = NoticeMapping.friendlyNumber(key),
            path == nil || Self.trimmedSlash(path ?? "") == taskPage
        {
            return .task(number: number, web: taskPage.flatMap(sameHost))
        }
        guard let url = (path ?? taskPage).flatMap(sameHost) else { return .none }
        return .web(url)
    }

    private func sameHost(_ path: String) -> URL? { WebAddress.page(path, on: webBase) }

    private static func trimmedSlash(_ path: String) -> String {
        var path = path
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

/// Filtering, grouping and row rules for the inbox. Pure, so every rule is unit tested.
enum NoticeRules {
    static func matches(_ kind: NoticeKind, _ filter: NoticeFilter) -> Bool {
        switch filter {
        case .all: true
        case .tasks: kind == .taskAssigned || kind == .taskActivity
        case .approvals: kind == .approval || kind == .signature
        case .meetings: kind == .meeting
        }
    }

    static func row(_ notice: Notice, links: NoticeLinks, now: Date, zone: TimeZone) -> NoticeRow {
        NoticeRow(
            id: notice.id,
            kind: notice.kind,
            title: notice.title,
            message: notice.message,
            at: notice.createdAt.map { TimeLabels.past($0, now: now, zone: zone) },
            isUnread: !notice.isRead,
            opensOutside: { if case .web = links.destination(notice) { true } else { false } }()
        )
    }

    /// Newest first under Today, Yesterday, This week and Earlier, in the employee's zone.
    static func groups(
        _ notices: [Notice],
        filter: NoticeFilter,
        links: NoticeLinks,
        now: Date,
        zone: TimeZone
    ) -> [NoticeGroup] {
        let today = CalendarDate(now, in: zone)
        let sorted = notices.filter { matches($0.kind, filter) }.sorted(by: newestFirst)
        var groups: [NoticeDay: [NoticeRow]] = [:]
        for notice in sorted {
            let day = day(notice.createdAt.map { CalendarDate($0, in: zone) }, today: today)
            groups[day, default: []].append(row(notice, links: links, now: now, zone: zone))
        }
        return groups.keys.sorted().map { NoticeGroup(day: $0, rows: groups[$0] ?? []) }
    }

    /// Unread notifications that ask the person to act, newest first.
    static func needsYou(_ notices: [Notice], links: NoticeLinks, now: Date, zone: TimeZone) -> [NoticeRow] {
        notices.filter { !$0.isRead && $0.asksForAction }.sorted(by: newestFirst).map {
            row($0, links: links, now: now, zone: zone)
        }
    }

    static func day(_ date: CalendarDate?, today: CalendarDate) -> NoticeDay {
        guard let date else { return .earlier }
        if date >= today { return .today }
        if date == today.adding(days: -1) { return .yesterday }
        if date >= today.adding(days: -6) { return .thisWeek }
        return .earlier
    }

    private static func newestFirst(_ lhs: Notice, _ rhs: Notice) -> Bool {
        switch (lhs.createdAt, rhs.createdAt) {
        case (let left?, let right?) where left != right: left > right
        case (nil, .some): true
        case (.some, nil): false
        default: lhs.id > rhs.id
        }
    }
}
