import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import ChatFeature

/// A members source the test drives: the inbox, the viewer, the hub status and scripted answers.
@MainActor
final class MembersHarness {
    let inbox = StateCell(Resource<[Conversation]>())
    let viewer = StateCell<String?>("usr_me")
    let banner = StateCell(ConnectionBanner.hidden)
    let status = StateCell(RealtimeStatus(state: .connected, epoch: 1))
    let detailResult = LockedBox<Result<Conversation, WaiveraError>>(.failure(.notFound))
    let openResult = LockedBox<Result<Int, WaiveraError>>(.success(42))
    let calls = LockedBox<[String]>([])

    var source: GroupMembersSource {
        let inbox = inbox
        let viewer = viewer
        let banner = banner
        let status = status
        let detailResult = detailResult
        let openResult = openResult
        let calls = calls
        return GroupMembersSource(
            inbox: { inbox.stream() },
            detail: { id in
                calls.mutate { $0.append("detail:\(id)") }
                return try detailResult.value.get()
            },
            refresh: { calls.mutate { $0.append("refresh") } },
            openDirect: { userId in
                calls.mutate { $0.append("open:\(userId)") }
                return try openResult.value.get()
            },
            viewer: { viewer.stream() },
            banner: { banner.stream() },
            statuses: { status.stream() },
            retryConnection: { calls.mutate { $0.append("retryConnection") } }
        )
    }

    func model(_ id: Int = 12) -> GroupMembersModel {
        GroupMembersModel(channelID: id, source: source)
    }

    static func group(_ people: [ChatUser], id: Int = 12) -> Conversation {
        Conversation(id: id, kind: .group, viewerId: "usr_me", participants: people)
    }

    static func person(_ id: String, _ first: String?, _ last: String? = nil) -> ChatUser {
        ChatUser(id: id, firstName: first, lastName: last)
    }

    static let team: [ChatUser] = [
        person("usr_priya", "priya", "Raman"),
        person("usr_me", "Alex", "Rivera"),
        person("usr_jordan", "Jordan", "Lee"),
        person("usr_b", "Jordan", "Lee"),
        person("usr_priya", "Priya", "Raman"),
        person("  ", "Nobody"),
    ]
}

/// A value shared with `@Sendable` closures.
final class LockedBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func mutate(_ change: (inout Value) -> Void) {
        lock.withLock { change(&stored) }
    }
}

@Suite("Group members")
@MainActor
struct GroupMembersModelTests {
    @Test func rowsPutMeFirstThenSortByNameThenId() {
        let rows = MemberRules.rows(MembersHarness.group(MembersHarness.team), myUserId: "usr_me")
        #expect(rows.map(\.userId) == ["usr_me", "usr_b", "usr_jordan", "usr_priya"])
        #expect(rows.first?.isMe == true)
        #expect(rows.dropFirst().allSatisfy { !$0.isMe })
    }

    @Test func searchMatchesNamesIgnoringCaseAndSpaces() {
        let rows = MemberRules.rows(MembersHarness.group(MembersHarness.team), myUserId: "usr_me")
        #expect(MemberRules.filter(rows, query: "  JORDAN ").map(\.userId) == ["usr_b", "usr_jordan"])
        #expect(MemberRules.filter(rows, query: "").count == rows.count)
        #expect(MemberRules.filter(rows, query: "zz").isEmpty)
    }

    @Test func searchShowsOnlyAboveTenMembers() {
        var state = GroupMembersState(totalCount: 10)
        #expect(!state.showsSearch)
        state.totalCount = 11
        #expect(state.showsSearch)
    }

    @Test func loadingThenMembersFromTheCachedInbox() async {
        let harness = MembersHarness()
        let model = harness.model()
        let task = Task { await model.run() }
        #expect(model.state.content == .loading)
        harness.inbox.set(Resource(value: [MembersHarness.group(MembersHarness.team)], phase: .loaded))
        #expect(await eventually { model.state.content == .members })
        #expect(model.state.totalCount == 4)
        #expect(!harness.calls.value.contains { $0.hasPrefix("detail") }, "a cached group needs no fetch")
        task.cancel()
    }

    @Test func aGroupMissingFromTheInboxLoadsItsDetail() async {
        let harness = MembersHarness()
        harness.detailResult.value = .success(MembersHarness.group(MembersHarness.team))
        let model = harness.model()
        let task = Task { await model.run() }
        harness.inbox.set(Resource(value: [], phase: .loaded))
        #expect(await eventually { model.state.content == .members })
        #expect(harness.calls.value.contains("detail:12"))
        task.cancel()
    }

    @Test func aFailedLoadShowsTheErrorAndRetryRecovers() async {
        let harness = MembersHarness()
        harness.detailResult.value = .failure(.offline)
        let model = harness.model()
        let task = Task { await model.run() }
        harness.inbox.set(Resource(value: [], phase: .loaded))
        #expect(await eventually { model.state.content == .error(.offline) })
        harness.detailResult.value = .success(MembersHarness.group(MembersHarness.team))
        await model.retry()
        #expect(model.state.content == .members)
        task.cancel()
    }

    @Test func emptyAndNoMatchAreDifferentStates() async {
        let harness = MembersHarness()
        let model = harness.model()
        let task = Task { await model.run() }
        harness.inbox.set(Resource(value: [MembersHarness.group([])], phase: .loaded))
        #expect(await eventually { model.state.content == .empty })
        #expect(!model.state.isNoMatch)
        harness.inbox.set(Resource(value: [MembersHarness.group(MembersHarness.team)], phase: .loaded))
        #expect(await eventually { model.state.content == .members })
        model.query = "nobody here"
        #expect(model.state.content == .empty)
        #expect(model.state.isNoMatch)
        #expect(model.state.totalCount == 4, "the count under the title ignores the search")
        model.query = ""
        #expect(model.state.content == .members)
        task.cancel()
    }

    @Test func theHubComingBackRefetchesAndTheBannerFollowsTheConnection() async {
        let harness = MembersHarness()
        let model = harness.model()
        let task = Task { await model.run() }
        harness.inbox.set(Resource(value: [MembersHarness.group(MembersHarness.team)], phase: .loaded))
        #expect(await eventually { model.state.content == .members })
        harness.banner.set(.offline)
        #expect(await eventually { model.state.connection == .offline })
        harness.status.set(RealtimeStatus(state: .disconnected, epoch: 1))
        try? await Task.sleep(for: .milliseconds(30))
        #expect(!harness.calls.value.contains("refresh"), "going down alone does not refetch")
        harness.status.set(RealtimeStatus(state: .connected, epoch: 2))
        #expect(await eventually { harness.calls.value.contains("refresh") })
        harness.banner.set(.hidden)
        #expect(await eventually { model.state.connection == nil })
        await model.retryConnection()
        #expect(harness.calls.value.contains("retryConnection"))
        task.cancel()
    }

    @Test func messageOpensTheDirectChatOneAtATimeAndNeverWithMyself() async {
        let harness = MembersHarness()
        let model = harness.model()
        let task = Task { await model.run() }
        harness.inbox.set(Resource(value: [MembersHarness.group(MembersHarness.team)], phase: .loaded))
        #expect(await eventually { model.state.content == .members })
        #expect(await model.message("usr_me") == nil)
        #expect(!harness.calls.value.contains("open:usr_me"))
        #expect(await model.message("usr_priya") == 42)
        #expect(model.state.openingChatWith == nil)
        #expect(harness.calls.value.filter { $0.hasPrefix("open:") } == ["open:usr_priya"])
        task.cancel()
    }

    @Test func aFailedMessageShowsADismissibleTypedError() async {
        let harness = MembersHarness()
        harness.openResult.value = .failure(.offline)
        let model = harness.model()
        let task = Task { await model.run() }
        harness.inbox.set(Resource(value: [MembersHarness.group(MembersHarness.team)], phase: .loaded))
        #expect(await eventually { model.state.content == .members })
        #expect(await model.message("usr_jordan") == nil)
        #expect(model.state.messageError == .offline)
        #expect(model.state.openingChatWith == nil)
        model.dismissMessageError()
        #expect(model.state.messageError == nil)
        task.cancel()
    }

    @Test func membersCopyResolves() {
        #expect(ConversationStrings.members(1) == "1 member")
        #expect(ConversationStrings.members(18) == "18 members")
        #expect(ConversationStrings.text("members.show") == "Show members")
        #expect(ConversationStrings.format("members.message", "Priya Raman") == "Message Priya Raman")
    }
}
