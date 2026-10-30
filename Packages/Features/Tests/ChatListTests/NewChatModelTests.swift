import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ChatFeature

/// 02 §7: the people picker and the open-or-create logic.
@MainActor
final class NewChatHarness {
    let clock: ManualClock
    let fakes: FakeDataEnvironment
    let stub: StubConversations?
    let model: NewChatModel
    private var task: Task<Void, Never>?

    init(_ scenario: FakeDataEnvironment.Scenario = .demo, inbox: [Conversation]? = nil) {
        let clock = ManualClock()
        self.clock = clock
        fakes = FakeDataEnvironment.make(scenario, clock: clock)
        let stub = inbox.map { StubConversations($0, updatedAt: DemoData.now, clock: clock) }
        self.stub = stub
        model = NewChatModel(
            people: fakes.people,
            conversations: stub ?? fakes.chat,
            session: fakes.session,
            clock: clock
        )
    }

    func start() async {
        await fakes.environment.launch()
        task = Task { await model.start() }
    }

    func stop() { task?.cancel() }

    var names: [String] { model.state.people.map(\.name) }
}

@MainActor
struct NewChatModelTests {
    static let direct = Sample.conversation(#"{"id": 7, "participants": [\#(Sample.me), \#(Sample.priya)]}"#)
    static let group = Sample.conversation(
        #"{"id": 63, "participants": [\#(Sample.me), \#(Sample.priya), \#(Sample.jordan), \#(Sample.sam)]}"#
    )
    static let channel = Sample.conversation(
        #"{"id": 41, "participants": [\#(Sample.me), \#(Sample.jordan)], "channel": {"name": "north"}}"#
    )

    @Test("Loading, then the directory without me")
    func loadsDirectoryWithoutMe() async {
        let harness = NewChatHarness(.slow)
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.fakes.people.resource.refreshCount == 1 })
        #expect(harness.model.state.content == .loading)
        harness.clock.advance(by: 1)
        #expect(await eventually { harness.model.state.content == .people })
        #expect(harness.names == ["Jordan Lee", "Priya Raman", "Sam Ortiz"])
    }

    @Test("Error: the directory failed with nothing cached; Retry loads it")
    func directoryError() async {
        let harness = NewChatHarness(.failing)
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .error(.server(statusCode: 503)) })
        harness.fakes.people.resource.setControls(FakeControls())
        await harness.model.retryLoad()
        #expect(await eventually { harness.model.state.content == .people })
    }

    @Test("Empty: no staff at all, or nobody matching the search")
    func emptyStates() async {
        let harness = NewChatHarness(.empty)
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .empty })
        let demo = NewChatHarness()
        await demo.start()
        defer { demo.stop() }
        #expect(await eventually { demo.model.state.content == .people })
        demo.model.query = "zz"
        #expect(demo.model.state.content == .empty)
    }

    @Test("Search matches the display name only, case-insensitive")
    func search() async {
        let harness = NewChatHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .people })
        harness.model.query = "  pri "
        #expect(harness.names == ["Priya Raman"])
        harness.model.query = "usr_"
        #expect(harness.names.isEmpty)
    }

    @Test("Selecting one says Open chat; two or more say Create group chat")
    func actionLabel() async {
        let harness = NewChatHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .people })
        #expect(!harness.model.state.canSubmit)
        harness.model.toggle("usr_priya_raman")
        #expect(harness.model.state.action == .openChat)
        #expect(harness.model.state.people.first { $0.id == "usr_priya_raman" }?.isSelected == true)
        harness.model.toggle("usr_jordan_lee")
        #expect(harness.model.state.action == .createGroup)
        #expect(harness.model.state.selectedCount == 2)
        harness.model.toggle("usr_jordan_lee")
        #expect(harness.model.state.selectedCount == 1)
    }

    @Test("An existing direct chat with exactly that person opens with no create request")
    func reusesDirect() async {
        let harness = NewChatHarness(inbox: [Self.channel, Self.group, Self.direct])
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .people })
        await settle()
        harness.model.toggle("usr_priya_raman")
        let opened = await harness.model.submit()
        #expect(opened == 7)
        #expect(harness.stub?.calls.count("create") == 0)
        #expect(harness.model.state.selectedCount == 0)
    }

    @Test("Matching is an exact, order-insensitive set: a subset or a channel never matches")
    func exactSetMatch() {
        let inbox = [Self.channel, Self.group, Self.direct]
        #expect(
            NewChatModel.match(
                ["usr_sam_ortiz", "usr_jordan_lee", "usr_priya_raman"],
                in: inbox,
                viewerId: Sample.viewer
            ) == 63
        )
        #expect(NewChatModel.match(["usr_priya_raman", "usr_jordan_lee"], in: inbox, viewerId: Sample.viewer) == nil)
        #expect(NewChatModel.match(["usr_jordan_lee"], in: inbox, viewerId: Sample.viewer) == nil)
        #expect(NewChatModel.match([Sample.viewer], in: inbox, viewerId: Sample.viewer) == nil)
    }

    @Test("A new group is created with each picked person once")
    func createsGroup() async {
        let harness = NewChatHarness(inbox: [Self.direct])
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .people })
        harness.model.toggle("usr_jordan_lee")
        harness.model.toggle("usr_sam_ortiz")
        let opened = await harness.model.submit()
        #expect(opened == 9_000)
        #expect(harness.stub?.calls.all == ["create:usr_jordan_lee,usr_sam_ortiz"])
    }

    @Test("A 409 refreshes the inbox and opens the matching conversation instead of an error")
    func conflictRecovers() async {
        let harness = NewChatHarness(inbox: [Self.direct])
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .people })
        harness.stub?.createFailure.update { $0 = .conflict }
        let existing = Sample.conversation(
            #"{"id": 70, "participants": [\#(Sample.me), \#(Sample.jordan), \#(Sample.sam)]}"#
        )
        harness.stub?.afterRefresh.update { $0 = [Self.direct, existing] }
        harness.model.toggle("usr_sam_ortiz")
        harness.model.toggle("usr_jordan_lee")
        let opened = await harness.model.submit()
        #expect(opened == 70)
        #expect(harness.stub?.calls.count("refresh") == 1)
        #expect(harness.model.state.error == nil)
    }

    @Test("A failure with no match after the refresh shows the typed error and keeps the selection")
    func failureShowsError() async {
        let harness = NewChatHarness(inbox: [Self.direct])
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .people })
        harness.stub?.createFailure.update { $0 = .offline }
        harness.model.toggle("usr_jordan_lee")
        let opened = await harness.model.submit()
        #expect(opened == nil)
        #expect(harness.model.state.error == .offline)
        #expect(harness.model.state.selectedCount == 1)
        #expect(!harness.model.state.isCreating)
        harness.model.toggle("usr_sam_ortiz")
        #expect(harness.model.state.error == nil)
    }

    @Test("Closing the sheet clears the search and the selection")
    func reset() async {
        let harness = NewChatHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .people })
        harness.model.query = "pri"
        harness.model.toggle("usr_priya_raman")
        harness.model.reset()
        #expect(harness.model.query.isEmpty)
        #expect(harness.model.state.selectedCount == 0)
        #expect(harness.names.count == 3)
    }

    @Test("Against the fake chat, a new direct chat is created and listed")
    func createsAgainstFakeChat() async {
        let harness = NewChatHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .people })
        harness.model.toggle("usr_sam_ortiz")
        let opened = await harness.model.submit()
        #expect(opened != nil)
        #expect(opened != 7)
    }

    @Test("Reconnect: a directory refetch keeps the people already picked and the search")
    func selectionSurvivesRefetch() async {
        let harness = NewChatHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .people })
        harness.model.toggle("usr_priya_raman")
        harness.model.query = "pri"
        let before = harness.fakes.people.resource.refreshCount
        await harness.fakes.people.refresh()
        #expect(await eventually { harness.fakes.people.resource.refreshCount == before + 1 })
        await settle()
        #expect(harness.names == ["Priya Raman"])
        #expect(harness.model.state.people.first?.isSelected == true)
        #expect(harness.model.state.selectedCount == 1)
        #expect(harness.model.state.content == .people)
    }

    @Test("Picking keeps the list in place: rows keep their order and only the picked one changes")
    func pickingKeepsOrder() async {
        let harness = NewChatHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .people })
        let order = harness.names
        harness.model.toggle("usr_sam_ortiz")
        #expect(harness.names == order)
        #expect(harness.model.state.people.map(\.isSelected) == [false, false, true])
    }
}
