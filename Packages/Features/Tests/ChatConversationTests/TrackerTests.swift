import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import ChatFeature

@Suite("Send and arrival trackers")
struct TrackerTests {
    private let base = Fixture.base

    @Test func failuresAlreadyThereOnOpenDoNotRaiseTheBanner() {
        var tracker = SendTracker()
        #expect(tracker.update([Fixture.outgoing("c1", state: .failed(.server(statusCode: 500)))]).newFailures.isEmpty)
    }

    @Test func aSendThatFailsWhileOpenIsReportedOnce() {
        var tracker = SendTracker()
        _ = tracker.update([])
        _ = tracker.update([Fixture.outgoing("c1")])
        #expect(tracker.update([Fixture.outgoing("c1", state: .failed(.offline))]).newFailures == [.offline])
        #expect(tracker.update([Fixture.outgoing("c1", state: .failed(.offline))]).newFailures.isEmpty)
    }

    @Test func aRetriedMessageThatLandsReportsSuccessOnce() {
        var tracker = SendTracker()
        _ = tracker.update([Fixture.outgoing("c1", state: .failed(.offline))])
        tracker.markRetried("c1")
        #expect(!tracker.update([Fixture.outgoing("c1", state: .queued(attempt: 1))]).retrySucceeded)
        #expect(tracker.update([]).retrySucceeded)
        #expect(!tracker.update([]).retrySucceeded)
    }

    @Test func aRetryThatFailsAgainIsAFailureNotASuccess() {
        var tracker = SendTracker()
        _ = tracker.update([Fixture.outgoing("c1", state: .failed(.offline))])
        tracker.markRetried("c1")
        _ = tracker.update([Fixture.outgoing("c1")])
        let events = tracker.update([Fixture.outgoing("c1", state: .failed(.offline))])
        #expect(events.newFailures.count == 1)
        #expect(!events.retrySucceeded)
    }

    @Test func aDiscardedRetryIsNotASuccess() {
        var tracker = SendTracker()
        _ = tracker.update([Fixture.outgoing("c1", state: .failed(.offline))])
        tracker.markRetried("c1")
        _ = tracker.update([Fixture.outgoing("c1")])
        tracker.markDiscarded("c1")
        #expect(!tracker.update([]).retrySucceeded)
    }

    private func entries(_ messages: [ChatMessage], _ pending: [OutgoingMessage] = []) -> [ArrivalTracker.Entry] {
        ArrivalTracker.entries(messages: messages, pending: pending)
    }

    @Test func theFirstLoadAndOlderPagesDoNotAnimate() {
        var tracker = ArrivalTracker()
        let ten = Fixture.message(10, at: base.addingTimeInterval(10))
        let eleven = Fixture.message(11, at: base.addingTimeInterval(11))
        #expect(tracker.update(entries([ten, eleven])).isEmpty)
        let older = Fixture.message(1, at: base.addingTimeInterval(-600))
        #expect(tracker.update(entries([older, ten, eleven])).isEmpty)
    }

    @Test func aNewerMessageAnimatesAndItsServerCopyDoesNotAnimateAgain() {
        var tracker = ArrivalTracker()
        let ten = Fixture.message(10, at: base.addingTimeInterval(10))
        _ = tracker.update(entries([ten]))
        let sending = Fixture.outgoing("c5", at: base.addingTimeInterval(60))
        #expect(tracker.update(entries([ten], [sending])) == ["client-c5"])
        let landed = Fixture.message(50, at: base.addingTimeInterval(60), clientId: "c5")
        #expect(tracker.update(entries([ten, landed])).isEmpty)
        let next = Fixture.message(51, at: base.addingTimeInterval(120))
        #expect(tracker.update(entries([ten, landed, next])) == ["message-51"])
    }

    @Test func anOwnSendIntoAnEmptyConversationAnimates() {
        var tracker = ArrivalTracker()
        _ = tracker.update([])
        #expect(tracker.update(entries([], [Fixture.outgoing("c1")])) == ["client-c1"])
    }
}
