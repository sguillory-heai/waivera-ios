import Foundation
import WaiveraAPI
import WaiveraData
import WaiveraDesign
import WaiveraTestSupport

@testable import ChatFeature

/// Records what the models ask the platform to do.
@MainActor
final class PlatformRecorder {
    var haptics: [HapticMoment] = []
    var copied: [String] = []
    var openedInApp: [URL] = []
    var openedExternally: [URL] = []

    var platform: ChatPlatform {
        ChatPlatform(
            copy: { [weak self] in self?.copied.append($0) },
            haptic: { [weak self] in self?.haptics.append($0) },
            openInApp: { [weak self] in self?.openedInApp.append($0) },
            openExternally: { [weak self] in self?.openedExternally.append($0) }
        )
    }
}

/// A fake data environment on a manual clock, with the session and hub started.
@MainActor
struct ModelHarness {
    let fakes: FakeDataEnvironment
    let clock: ManualClock
    let recorder = PlatformRecorder()

    init(
        _ scenario: FakeDataEnvironment.Scenario = .demo,
        webBaseURL: URL? = nil
    ) async {
        let clock = ManualClock()
        self.clock = clock
        fakes = FakeDataEnvironment.make(scenario, clock: clock, webBaseURL: webBaseURL)
        await fakes.session.start()
        await fakes.realtime.start()
    }

    var chatClock: ChatClock { ChatClock(clock: clock, timeZone: { Fixture.chicago }) }

    func conversation(
        _ id: Int = 7,
        target: Int? = nil,
        onOpenThread: @escaping @MainActor (Int, Int?) -> Void = { _, _ in }
    ) -> ConversationModel {
        ConversationModel(
            conversationID: id,
            targetMessageID: target,
            data: fakes.environment,
            clock: chatClock,
            platform: recorder.platform,
            onOpenThread: onOpenThread
        )
    }

    func thread(_ root: Int = 9330, conversation: Int? = 7, target: Int? = nil) -> ThreadModel {
        ThreadModel(
            rootMessageID: root,
            conversationID: conversation,
            targetMessageID: target,
            data: fakes.environment,
            clock: chatClock,
            platform: recorder.platform
        )
    }

    /// Advances the manual clock in small steps so chained sleeps all wake.
    func advance(by seconds: Double, steps: Int = 10) async {
        // Let the model reach its sleep first; an advance before it would be lost.
        _ = await eventually(timeout: 1) { clock.pendingSleepers > 0 }
        for _ in 0..<steps {
            clock.advance(by: seconds / Double(steps))
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

extension ConversationModel {
    var pendingRows: [PendingRow] {
        state.items.compactMap { item in
            if case .pending(let row) = item { return row }
            return nil
        }
    }

    var messageRows: [MessageRow] {
        state.items.compactMap { item in
            if case .message(let row) = item { return row }
            return nil
        }
    }
}

extension ConversationModel {
    /// Messages shown and the conversation row loaded (write permission known).
    var isReady: Bool { state.content == .messages && state.canWrite != nil }
}
