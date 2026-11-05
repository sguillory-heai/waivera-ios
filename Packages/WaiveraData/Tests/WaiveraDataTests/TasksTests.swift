import Foundation
import Testing
import WaiveraAPI

@testable import WaiveraData

@Suite("Tasks")
struct TasksTests {
    private let me = CurrentUser(id: "u-alex", firebaseUid: "fb-alex")

    private let listPage = #"""
        {"tasks":[
          {"id":12,"friendlyId":1042,"title":" Intake review ","organization":{"abbreviation":"HEA"},
           "endDate":"2026-11-08T00:00:00","effectiveEndDate":"2026-11-10T00:00:00",
           "taskStatus":{"id":1,"name":"In Progress"},"participant":{"firstName":"Jordan","lastName":"Lee"},
           "assignees":[{"user":{"id":"u-rep","firstName":"Rae"},"isReporter":true},
                        {"user":{"id":"u-co","firstName":"Cory"},"isCoAssignee":true},
                        {"user":{"id":"u-alex","displayName":"Alex Rivera"}}],
           "hasPendingDeletion":true,
           "currentTaskDelay":{"reasonName":"Hospital stay","delayEndDate":"2026-11-20"}},
          {"id":13,"friendlyId":7,"title":"Training","taskStatus":{"name":"WEIRD"}, "subjectEmployee":{"firstName":"Alex"}},
          {"id":"bad"}
        ],"totalCount":41}
        """#

    private func make() async -> (LiveTasksRepository, LiveRequestsRepository, RoutingTransport) {
        let transport = RoutingTransport()
        await transport.set("GET api/tasks/user/u-alex", .json(listPage))
        await transport.set(
            "POST api/Authentication/bootstrap",
            .json(#"{"data":{"roles":{"employeeRoles":[{"name":"Supervisor"}]},"rolePolicies":[]},"success":true}"#)
        )
        let context = SessionContext(user: me)
        let api = makeAPI(transport)
        let requests = LiveRequestsRepository(api: api, context: context)
        return (LiveTasksRepository(api: api, context: context, requests: requests), requests, transport)
    }

    @Test func mapsSummariesWithKeysDatesAssigneeAndDelay() async throws {
        let (repository, _, transport) = await make()
        let page = try await repository.tasks(TaskQuery(scope: .casework, window: .dueSoon), page: 1)
        #expect(page.totalCount == 41)
        #expect(page.items.count == 2)
        let first = page.items[0]
        #expect(first.key == "HEA-1042")
        #expect(first.title == "Intake review")
        #expect(first.due == CalendarDate(year: 2026, month: 11, day: 10))
        #expect(first.state == .inProgress)
        #expect(first.about == "Jordan Lee")
        #expect(first.assigneeId == "u-alex")
        #expect(first.assigneeName == "Alex Rivera")
        #expect(first.pendingClosure)
        #expect(first.delayed)
        #expect(first.delayedThrough == CalendarDate(year: 2026, month: 11, day: 20))
        #expect(page.items[1].key == "7")
        #expect(page.items[1].state == .other("WEIRD"))
        #expect(page.items[1].about == "Alex")

        let url = await transport.requests.last?.url?.absoluteString ?? ""
        #expect(!url.contains("assignee="))
        #expect(url.contains("taskContext=Client"))
        #expect(url.contains("includePendingApprovals=true"))
        #expect(url.contains("date=month"))
        #expect(url.contains("excludeStatus=CLOSED"))
    }

    @Test func myWorkAsksForTheEmployeeContextWithoutDelays() async throws {
        let (repository, _, transport) = await make()
        _ = try await repository.tasks(
            TaskQuery(scope: .mine, window: .overdue, search: " cpr ", delays: .only),
            page: 2
        )
        let url = await transport.requests.last?.url?.absoluteString ?? ""
        #expect(url.contains("assignee=u-alex"))
        #expect(url.contains("taskContext=Employee"))
        #expect(url.contains("searchTerm=cpr"))
        #expect(!url.contains("taskDelayFilter"))
        #expect(!url.contains("includePendingApprovals"))
        #expect(url.contains("page=2"))
    }

    @Test func countsLeaveDelaysOutOfOverdue() async throws {
        let (repository, _, transport) = await make()
        let counts = try await repository.counts(scope: .casework, assignedToMe: true)
        #expect(counts == TaskCounts(open: 41, overdue: 41, delayed: 41))
        let urls = await transport.requests.compactMap { $0.url?.absoluteString }.filter { $0.contains("tasks/user") }
        #expect(urls.contains { $0.contains("date=overdue") && $0.contains("taskDelayFilter=without-delays") })
        #expect(urls.contains { $0.contains("taskDelayFilter=delayed") })
    }

    @Test func detailPicksAssigneeFromAssigneesAndNewestPendingRequest() {
        let dto = TaskResponse(
            id: 12,
            friendlyId: 1042,
            title: "Intake",
            organization: TaskOrganizationResponse(abbreviation: "HEA"),
            startDate: "2026-11-01T00:00:00",
            endDate: "2026-11-08T00:00:00",
            taskStatus: NamedStatusResponse(name: "Completed"),
            reporter: TaskUserResponse(firstName: "Rae", lastName: "Kim"),
            assignees: [
                TaskAssignmentResponse(user: TaskUserResponse(firstName: "Rae"), isReporter: true),
                TaskAssignmentResponse(user: TaskUserResponse(firstName: "Cory"), isCoAssignee: true),
                TaskAssignmentResponse(user: TaskUserResponse(firstName: "Dana", lastName: "Cole")),
            ],
            taskContext: "Employee",
            administrativeTransactionRequests: [
                AdminRequestResponse(
                    id: 1,
                    transactionType: "Task Extension Request",
                    status: "PENDING",
                    requestTime: "2026-11-01T10:00:00Z"
                ),
                AdminRequestResponse(
                    id: 2,
                    transactionType: "Task Delay Request",
                    status: "PENDING",
                    requestTime: "2026-11-02T10:00:00Z"
                ),
                AdminRequestResponse(
                    id: 3,
                    transactionType: "Task Delay Request",
                    status: "APPROVED",
                    requestTime: "2026-11-03T10:00:00Z"
                ),
            ]
        )
        let detail = TaskMapping.detail(dto)
        #expect(detail.assigneeName == "Dana Cole")
        #expect(detail.assignedBy == "Rae Kim")
        #expect(detail.webPath == "/task/HEA-1042")
        #expect(!detail.isClientTask)
        #expect(detail.isFinished)
        #expect(detail.pendingRequest?.id == 2)
        #expect(detail.pendingRequest?.kind == .delay)
    }

    @Test func activityIsTopLevelOldestFirstInSentenceCase() {
        let items = [
            TaskActionResponse(
                id: 3,
                actionSubType: ActionSubTypeResponse(actionSubTypeName: "PHONE CALL"),
                createDate: "2026-11-03T15:00:00Z",
                durationInMinutes: 15
            ),
            TaskActionResponse(id: 1, description: "Removed", createDate: "2026-11-01T15:00:00Z", deleted: true),
            TaskActionResponse(
                id: 2,
                description: " Visit ",
                completionTime: "2026-11-02T15:00:00",
                durationInMinutes: -4
            ),
            TaskActionResponse(id: 4, createDate: "2026-11-04T15:00:00Z", parentTaskActionId: 3),
            TaskActionResponse(id: 5),
        ]
        let activity = TaskMapping.activity(items)
        #expect(activity.map(\.id) == [5, 2, 3])
        #expect(activity[1].minutes == 0)
        #expect(activity[1].description == "Visit")
        #expect(activity[2].type == "Phone call")
        // A chat-style UTC time without a zone suffix is still UTC.
        #expect(activity[1].at == WaiveraInstant.parse("2026-11-02T15:00:00Z"))
    }

    @Test func attachmentsSkipRemovedAndSortNewestFirst() {
        let items = [
            TaskAttachmentResponse(
                id: 1,
                file: TaskAttachmentFileResponse(
                    id: "f1",
                    fileName: "Plan.PDF",
                    size: 10,
                    createDate: "2026-11-01T00:00:00Z"
                )
            ),
            TaskAttachmentResponse(
                id: 2,
                file: TaskAttachmentFileResponse(
                    id: "f2",
                    fileName: "notes",
                    mimeType: "text/plain",
                    createDate: "2026-11-03T00:00:00Z"
                ),
                fileStorageKind: "employeeFile"
            ),
            TaskAttachmentResponse(id: 3, file: TaskAttachmentFileResponse(id: " ")),
            TaskAttachmentResponse(id: 4, file: TaskAttachmentFileResponse(id: "f4"), employeeFileDeleted: true),
        ]
        let files = TaskMapping.attachments(items)
        #expect(files.map(\.attachmentId) == [2, 1])
        #expect(files[0].kind == .text)
        #expect(files[0].employeeFile)
        #expect(files[1].kind == .pdf)
        #expect(files[1].viewable)
    }

    @Test func fileKindsByExtensionThenType() {
        #expect(FileKind(name: "a.docx", mimeType: nil) == .word)
        #expect(FileKind(name: "a.heic", mimeType: nil) == .image)
        #expect(FileKind(name: "a.xlsx", mimeType: "application/pdf") == .other)
        #expect(FileKind(name: "scan", mimeType: "image/png") == .image)
        #expect(FileKind(name: "scan", mimeType: nil) == .other)
    }

    @Test func activityTypesKeepLoggableTypesAndNameTheirFileTemplate() {
        let types = TaskMapping.activityTypes(
            [
                ActionSubTypeResponse(
                    id: 1,
                    actionSubTypeName: "VISIT",
                    recommendedTimeInMinutes: 0,
                    isUserLoggable: true
                ),
                ActionSubTypeResponse(id: 2, actionSubTypeName: "Upload", requiresFile: 7, isUserLoggable: true),
                ActionSubTypeResponse(
                    id: 3,
                    actionSubTypeName: "Call",
                    recommendedTimeInMinutes: 15,
                    description: "Phone",
                    isUserLoggable: true
                ),
                ActionSubTypeResponse(id: 4, actionSubTypeName: "System", isUserLoggable: false),
                ActionSubTypeResponse(id: 5, actionSubTypeName: "Fax", requiresFile: 99, isUserLoggable: true),
            ],
            templates: [
                TemplateFileResponse(
                    id: 7,
                    fileName: " Signed plan ",
                    type: FileTypeResponse(id: 4),
                    employeeDocumentCategoryId: 2
                )
            ]
        )
        #expect(types.map(\.id) == [3, 5, 2, 1])
        #expect(types[0].recommendedMinutes == 15 && !types[0].needsFile)
        #expect(types[0].fixedDescription == "Phone")
        // A template the organization no longer has: the file keeps its own name.
        #expect(types[1].needsFile && types[1].fileTemplate == nil)
        #expect(types[2].fileTemplate == FileTemplate(id: 7, name: "Signed plan", typeId: 4, categoryId: 2))
        #expect(types[3].recommendedMinutes == nil)
    }

    @Test func logActivitySendsUTCCompletionTime() async throws {
        let (repository, _, transport) = await make()
        await transport.set("POST api/taskActions/new", .json(#"{"data":9,"success":true}"#))
        let at = try #require(WaiveraInstant.parse("2026-11-01T06:30:00Z"))
        try await repository.logActivity(
            NewActivity(taskId: 12, typeId: 3, minutes: 30, completedAt: at, description: " Called mom ")
        )
        let body = try #require(await transport.bodies("POST api/taskActions/new").first)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["description"] as? String == "Called mom")
        #expect((json?["completionTime"] as? String)?.hasPrefix("2026-11-01T06:30:00") == true)

        await transport.set("POST api/taskActions/new", .json(#"{"data":null,"success":false,"statusCode":400}"#))
        await #expect(throws: WaiveraError.self) {
            try await repository.logActivity(
                NewActivity(taskId: 12, typeId: 3, minutes: 30, completedAt: at, description: "x")
            )
        }
    }
}

@Suite("Requests")
struct RequestsTests {
    private let me = CurrentUser(id: "u-alex", firebaseUid: "fb-alex")

    private func make() async -> (LiveRequestsRepository, RoutingTransport) {
        let transport = RoutingTransport()
        let waiting = #"""
            {"data":{"items":[
              {"id":5,"transactionType":"Task Extension Request","status":"PENDING","requesterName":"Dana",
               "extensionReason":"Family","transactionReasonText":"Needs a week","extensionOriginalDueDate":"2026-11-03",
               "extensionRequestedDueDate":"2026-11-10T00:00:00Z","taskId":12},
              {"id":6,"transactionType":"Task Delay Request","status":"PENDING","delayReason":"Hospital",
               "delayStartDate":"2026-11-01","delayEndDate":"2026-11-15"}
            ],"totalCount":2},"success":true}
            """#
        await transport.set("GET api/admin/request/pending-approvals", .json(waiting))
        return (LiveRequestsRepository(api: makeAPI(transport), context: SessionContext(user: me)), transport)
    }

    @Test func waitingMapsKindsReasonsAndDates() async throws {
        let (repository, _) = await make()
        try await repository.refreshWaiting()
        let list = try #require(await latest(repository.waiting()) ?? nil)
        #expect(list.map(\.id) == [5, 6])
        #expect(list[0].kind == .moreTime)
        #expect(list[0].reason == "Family")
        #expect(list[0].explanation == "Needs a week")
        #expect(list[0].requestedDue == CalendarDate(year: 2026, month: 11, day: 10))
        #expect(list[1].kind == .delay)
        #expect(list[1].delayEnd == CalendarDate(year: 2026, month: 11, day: 15))
    }

    @Test func aRefusedDecisionComesBackInPlaceAndATakenOneStaysGone() async throws {
        let (repository, transport) = await make()
        try await repository.refreshWaiting()
        let list = try #require(await latest(repository.waiting()) ?? nil)
        await transport.set("PUT api/admin/request/approve/5", .status(500))
        await #expect(throws: WaiveraError.self) { try await repository.decide(list[0], approve: true) }
        #expect((await latest(repository.waiting()) ?? nil)?.map(\.id) == [5, 6])

        await transport.set("PUT api/admin/request/reject/6", .status(404))
        await #expect(throws: WaiveraError.self) { try await repository.decide(list[1], approve: false) }
        #expect((await latest(repository.waiting()) ?? nil)?.map(\.id) == [5])

        await transport.set("PUT api/admin/request/approve/5", .json(#"{"success":true}"#))
        try await repository.decide(list[0], approve: true)
        #expect((await latest(repository.waiting()) ?? nil)?.isEmpty == true)
    }

    /// A page that was already on its way when a decision landed still lists the request; it
    /// must not bring it back. A page asked for after the decision is the server's word again.
    @Test func aStalePageNeverBringsBackAJustDecidedRequest() async throws {
        let (repository, transport) = await make()
        try await repository.refreshWaiting()
        let list = try #require(await latest(repository.waiting()) ?? nil)
        let gate = PageGate()
        await transport.setBeforeReply { request in
            guard request.url?.path.contains("pending-approvals") == true else { return }
            await gate.wait()
        }
        let stale = Task { try await repository.refreshWaiting() }
        while await gate.waiting == 0 { try await Task.sleep(for: .milliseconds(2)) }
        await transport.set("PUT api/admin/request/approve/5", .json(#"{"success":true}"#))
        try await repository.decide(list[0], approve: true)
        await gate.open()
        try await stale.value
        #expect((await latest(repository.waiting()) ?? nil)?.map(\.id) == [6])

        try await repository.refreshWaiting()
        #expect((await latest(repository.waiting()) ?? nil)?.map(\.id) == [5, 6])
    }

    @Test func eligibilityFailsClosedOnAReversedPeriod() {
        let open = RequestMapping.options(
            ComplianceEligibilityResponse(
                canRequestExtension: true,
                canRequestDelay: true,
                delayStartDate: "2026-11-01",
                delayEndDate: "2026-11-15"
            ),
            taskId: 12
        )
        #expect(open.canAskMoreTime)
        #expect(open.delay?.end == CalendarDate(year: 2026, month: 11, day: 15))
        let reversed = RequestMapping.options(
            ComplianceEligibilityResponse(
                canRequestDelay: true,
                delayStartDate: "2026-11-15",
                delayEndDate: "2026-11-01"
            ),
            taskId: 12
        )
        #expect(reversed.delay == nil)
        let pending = RequestMapping.options(
            ComplianceEligibilityResponse(hasPendingRequest: true, canRequestExtension: true),
            taskId: 12
        )
        #expect(!pending.canAskMoreTime)
    }

    @Test func accessFollowsTheWebRules() {
        let supervisor = AuthBootstrapResponse(
            roles: .init(employeeRoles: ["Supervisor"]),
            rolePolicyKeys: [RequestMapping.createExtension],
            userAddedInRolePolicy: true
        )
        let access = RequestMapping.access(supervisor)
        #expect(access.canAskMoreTime)
        #expect(!access.canAskClosure)
        #expect(access.includePendingApprovals)
        #expect(access.showsRequests)

        let coordinator = AuthBootstrapResponse(
            roles: .init(employeeRoles: ["SC", "Supervisor"], organizationRoles: [.init(name: "Office Manager")]),
            userAddedInRolePolicy: false
        )
        let other = RequestMapping.access(coordinator)
        // A legacy account without policies passes, as on the web.
        #expect(other.canAskClosure)
        #expect(!other.includePendingApprovals)
        #expect(!other.showsRequests)
    }

    @Test func moreTimeSendsTheDayAtUTCMidnight() async throws {
        let (repository, transport) = await make()
        await transport.set("POST api/tasks/12/extensions", .json(#"{"adjustmentId":1,"status":"Approved"}"#))
        let due = try #require(CalendarDate(year: 2026, month: 3, day: 8))
        let outcome = try await repository.askMoreTime(
            taskId: 12,
            newDue: due,
            reasonId: 4,
            explanation: " Busy ",
            evidenceId: nil
        )
        #expect(outcome == .approved)
        let body = try #require(await transport.bodies("POST api/tasks/12/extensions").first)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["requestedDueDate"] as? String == "2026-03-08T00:00:00Z")
        #expect(json?["explanation"] as? String == "Busy")
    }

    @Test func closureNamesTheRequesterAndSignOutClearsEverything() async throws {
        let (repository, transport) = await make()
        await transport.set("POST api/tasks/12/request-close", .json(#"{"success":true}"#))
        try await repository.askClosure(taskId: 12, reasonId: 3, comment: "Duplicate")
        let body = try #require(await transport.bodies("POST api/tasks/12/request-close").first)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["requesterId"] as? String == "u-alex")
        #expect(json?["transactionTypeId"] as? String == "Task Deletion Request")

        try await repository.refreshWaiting()
        await repository.reset()
        #expect((await latest(repository.waiting()) ?? nil) == nil)
        #expect(await repository.currentAccess().loaded == false)
    }
}
