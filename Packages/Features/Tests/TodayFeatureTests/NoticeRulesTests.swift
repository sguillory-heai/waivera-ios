import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import TodayFeature

/// The inbox's filters, day groups (across the DST change), links and Needs you rows.
struct NoticeRulesTests {
    private let links = NoticeLinks(webBase: URL(string: "https://app.waivera.com"))

    private func notice(
        _ id: String,
        _ kind: NoticeKind,
        at raw: String?,
        read: Bool = false,
        taskKey: String? = nil,
        webPath: String? = nil
    ) -> Notice {
        Notice(
            id: id,
            kind: kind,
            title: id,
            message: "",
            createdAt: raw.map(Fixture.instant),
            isRead: read,
            taskKey: taskKey,
            webPath: webPath
        )
    }

    @Test func groupsByDayInTheEmployeesZoneAcrossDST() {
        // Fixture.now is 10:30 CST on 1 Nov 2026, the morning clocks fell back.
        let items = [
            notice("today", .taskActivity, at: "2026-11-01T05:30:00Z"),  // 00:30 CDT, today
            notice("yesterday", .meeting, at: "2026-11-01T04:59:00Z"),  // 23:59 CDT 31 Oct
            notice("week", .approval, at: "2026-10-27T15:00:00Z"),
            notice("old", .survey, at: "2026-10-10T15:00:00Z"),
            notice("undated", .other, at: nil),
        ]
        let groups = NoticeRules.groups(items, filter: .all, links: links, now: Fixture.now, zone: Fixture.chicago)
        #expect(groups.map(\.day) == [.today, .yesterday, .thisWeek, .earlier])
        #expect(groups.last?.rows.map(\.id) == ["undated", "old"])
    }

    @Test func filtersPutSignaturesWithApprovals() {
        #expect(NoticeRules.matches(.signature, .approvals))
        #expect(NoticeRules.matches(.taskAssigned, .tasks))
        #expect(!NoticeRules.matches(.meeting, .tasks))
    }

    /// `/task/{key}` names the friendly reference, as the web reads it, so the shell looks the
    /// number up; deeper pages about the task stay on the web.
    @Test func linksOpenTasksInAppAndOtherPagesOnTheSameHostOnly() {
        let page = URL(string: "https://app.waivera.com/task/HEA-42")
        #expect(
            links.destination(notice("a", .taskAssigned, at: nil, taskKey: "HEA-42")) == .task(number: 42, web: page)
        )
        #expect(
            links.destination(notice("b", .taskActivity, at: nil, taskKey: "HEA-42", webPath: "/task/HEA-42/"))
                == .task(number: 42, web: page)
        )
        #expect(
            links.destination(notice("n", .taskActivity, at: nil, taskKey: "42"))
                == .task(number: 42, web: URL(string: "https://app.waivera.com/task/42"))
        )
        let files = links.destination(
            notice("c", .taskActivity, at: nil, taskKey: "HEA-42", webPath: "/task/HEA-42/files")
        )
        #expect(files == .web(URL(string: "https://app.waivera.com/task/HEA-42/files")!))
        #expect(links.destination(notice("d", .other, at: nil, webPath: "//evil.example/x")) == .none)
        #expect(links.destination(notice("p", .other, at: nil, webPath: "https://app.waivera.com:8443/x")) == .none)
        #expect(NoticeLinks(webBase: nil).destination(notice("e", .signature, at: nil, webPath: "/esign")) == .none)
    }

    @Test func taskKeysAreFriendlyReferences() {
        #expect(NoticeMapping.taskKey(in: "/task/HEA-1042?section=chat") == "HEA-1042")
        #expect(NoticeMapping.taskKey(in: "/task/1042") == "1042")
        #expect(NoticeMapping.taskKey(in: "/task/HEA-") == nil)
        #expect(NoticeMapping.taskKey(in: "/task/A-B-1") == nil)
        #expect(NoticeMapping.friendlyNumber("hea-0") == nil)
        #expect(NoticeMapping.friendlyNumber("HEA-1042") == 1042)
    }

    @Test func needsYouHoldsUnreadActionsOnly() {
        let rows = NoticeRules.needsYou(
            [
                notice("assigned", .taskAssigned, at: "2026-11-01T15:00:00Z"),
                notice("read", .approval, at: "2026-11-01T16:00:00Z", read: true),
                notice("meeting", .meeting, at: "2026-11-01T16:10:00Z"),
            ],
            links: links,
            now: Fixture.now,
            zone: Fixture.chicago
        )
        #expect(rows.map(\.id) == ["assigned"])
    }

    /// Request notifications never update when another approver decides, so Needs you leaves
    /// them to the live pending list; the inbox still shows them.
    @Test func needsYouLeavesRequestNotificationsToThePendingList() {
        var request = notice("request", .approval, at: "2026-11-01T16:00:00Z")
        request.opensRequests = true
        let notices = [notice("assigned", .taskAssigned, at: "2026-11-01T15:00:00Z"), request]
        let rows = NoticeRules.needsYou(notices, links: links, now: Fixture.now, zone: Fixture.chicago)
        #expect(rows.map(\.id) == ["assigned"])
        let inbox = NoticeRules.groups(
            notices,
            filter: .all,
            links: links,
            now: Fixture.now,
            zone: Fixture.chicago
        )
        #expect(inbox.flatMap(\.rows).map(\.id).contains("request"))
    }

    @Test func pendingRequestsBecomeApprovalCards() {
        let rows = NoticeRules.requests(
            [
                ChangeRequest(
                    id: 81,
                    kind: .profileChange,
                    typeName: "Profile Change",
                    status: .pending,
                    requesterId: "u1",
                    requesterName: "Jordan Lee",
                    requestedAt: Fixture.instant("2026-11-01T15:00:00Z")
                ),
                ChangeRequest(
                    id: 82,
                    kind: .moreTime,
                    typeName: "Task Extension Request",
                    status: .pending,
                    requesterId: "u2",
                    requesterName: "Sam Ortiz",
                    taskId: 16,
                    taskTitle: "Monthly contact"
                ),
            ],
            now: Fixture.now,
            zone: Fixture.chicago
        )
        #expect(rows.map(\.id) == ["request-81", "request-82"])
        #expect(rows.allSatisfy { $0.kind == .approval && $0.isUnread && !$0.opensOutside })
        #expect(rows.map(\.title) == ["Profile Change", "Task Extension Request"])
        #expect(rows.map(\.message) == ["From Jordan Lee", "From Sam Ortiz · Monthly contact"])
        #expect(rows[0].at != nil)
        #expect(rows[1].at == nil)
    }
}
