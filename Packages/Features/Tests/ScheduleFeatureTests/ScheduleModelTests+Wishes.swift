import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ScheduleFeature

/// "Send wishes" on a celebration card and today's "Now" line, through the model.
@MainActor
@Suite("Schedule model wishes and now", .serialized)
struct ScheduleModelWishesTests {
    /// 10:30 CDT on Tuesday 27 Oct 2026.
    let morning = instant("2026-10-27T15:30:00Z")

    func model(conversations: TestConversations?, feed: CalendarFeed = CalendarFeed()) -> (ScheduleModel, ManualClock) {
        let clock = ManualClock(now: morning)
        let calendar = TestCalendarRepository(
            zone: Zones.chicago,
            today: CalendarDate(clock.now, in: Zones.chicago),
            feed: feed,
            clock: clock
        )
        let model = ScheduleModel(
            calendar: calendar,
            session: TestSession.signedIn(),
            realtime: TestRealtime(),
            conversations: conversations,
            clock: clock,
            deviceZone: { Zones.chicago },
            locale: english
        )
        return (model, clock)
    }

    @Test func sendWishesOpensTheDirectChatOnceAndShowsItIsBusy() async {
        let conversations = TestConversations()
        let (model, _) = model(conversations: conversations)
        #expect(model.canSendWishes)
        model.sendWishes(to: "u2")
        #expect(model.state.openingWishesFor == "u2")
        // A second tap while the chat opens is ignored.
        model.sendWishes(to: "u3")
        #expect(await eventually { model.wishesRequest != nil })
        #expect(model.wishesRequest?.conversationId == 42)
        #expect(model.state.openingWishesFor == nil)
        #expect(conversations.calls.all == ["direct:u2"])
        if let request = model.wishesRequest { model.wishesHandled(request) }
        #expect(model.wishesRequest == nil)
    }

    @Test func failedWishesOfferRetryAndClearTheBusyLabel() async {
        let conversations = TestConversations()
        conversations.result.update { $0 = .failure(.offline) }
        let (model, _) = model(conversations: conversations)
        model.sendWishes(to: "u2")
        #expect(await eventually { model.wishesFailure != nil })
        #expect(model.wishesFailure?.userId == "u2")
        #expect(model.state.openingWishesFor == nil)
        conversations.result.update { $0 = .success(7) }
        model.sendWishes(to: "u2")
        #expect(model.wishesFailure == nil)
        #expect(await eventually { model.wishesRequest?.conversationId == 7 })
    }

    @Test func leavingTheScreenDropsAChatStillOpening() async {
        let conversations = TestConversations()
        conversations.delay.update { $0 = .milliseconds(200) }
        let (model, _) = model(conversations: conversations)
        let start = Task { await model.start() }
        model.sendWishes(to: "u2")
        #expect(model.state.openingWishesFor == "u2")
        start.cancel()
        #expect(await eventually { model.state.openingWishesFor == nil })
        try? await Task.sleep(for: .milliseconds(300))
        #expect(model.wishesRequest == nil)
        #expect(model.wishesFailure == nil)
    }

    @Test func noWishesToYourselfOrWithoutAChatRepository() async {
        let conversations = TestConversations()
        let (model, _) = model(conversations: conversations)
        model.sendWishes(to: "usr_me")
        #expect(model.state.openingWishesFor == nil)
        let (bare, _) = self.model(conversations: nil)
        #expect(!bare.canSendWishes)
        bare.sendWishes(to: "u2")
        #expect(bare.state.openingWishesFor == nil)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(conversations.calls.all.isEmpty)
    }

    @Test func nowLineMovesOnWhenTheScreenResumes() async {
        let visit = event("visit", "2026-10-27T11:00:00-05:00", "2026-10-27T12:00:00-05:00")
        let (model, clock) = model(conversations: nil, feed: CalendarFeed(events: [visit]))
        model.select(view: .day)
        let start = Task { await model.start() }
        let feed = Task { await model.observeFeed() }
        defer {
            start.cancel()
            feed.cancel()
        }
        #expect(await eventually { model.state.agendaNow != nil })
        #expect(model.state.agendaNow?.time == "10:30 AM")
        #expect(model.state.agendaNow?.beforeID == "event:visit")
        clock.advance(by: 2 * 3600)
        model.resume()
        #expect(model.state.agendaNow?.time == "12:30 PM")
        #expect(model.state.agendaNow?.endedIDs == ["event:visit"])
        #expect(model.state.agendaNow?.beforeID == nil)
    }
}

@MainActor
extension ScheduleModelWishesTests {
    @Test func stepsRecordTheirDirectionAndViewChangesFade() {
        let (model, _) = model(conversations: nil)
        model.step(1)
        #expect(model.state.periodStep == 1)
        model.step(-1)
        model.step(-1)
        #expect(model.state.periodStep == -1)
        model.select(view: .week)
        #expect(model.state.periodStep == 0)
        // A day in the same week keeps the period, so nothing slides.
        model.select(date: model.state.cells[0].date)
        #expect(model.state.periodStep == 0)
        model.step(1)
        model.resume()
        #expect(model.state.periodStep == 1)
    }
}
