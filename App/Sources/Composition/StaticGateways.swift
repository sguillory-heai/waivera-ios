import Foundation
import WaiveraNotifications

/// In-memory gateways. Used when the data layer is not configured (missing `.xcconfig`
/// values) and, in DEBUG, as the fake-server shell gateways.
final class StaticSessionGateway: SessionGateway {
    private var current: ShellSession
    private var continuations: [UUID: AsyncStream<ShellSession>.Continuation] = [:]

    init(_ initial: ShellSession) {
        current = initial
    }

    func states() -> AsyncStream<ShellSession> {
        let (stream, continuation) = AsyncStream<ShellSession>.makeStream()
        let id = UUID()
        continuations[id] = continuation
        continuation.yield(current)
        return stream
    }

    func signOut() async {
        set(.signedOut)
    }

    func set(_ state: ShellSession) {
        current = state
        for continuation in continuations.values {
            continuation.yield(state)
        }
    }
}

final class StaticPreferencesGateway: PreferencesGateway {
    private let value: ShellPreferences

    init(_ value: ShellPreferences = ShellPreferences()) {
        self.value = value
    }

    func values() -> AsyncStream<ShellPreferences> {
        let (stream, continuation) = AsyncStream<ShellPreferences>.makeStream()
        continuation.yield(value)
        return stream
    }
}

final class StaticHubStatus: HubStatusGateway {
    let isConnected: Bool

    init(isConnected: Bool) {
        self.isConnected = isConnected
    }
}

final class NoChatActions: ChatActionsGateway {
    func reply(conversationID: Int, threadRootMessageID: Int?, text: String) async {}
    func markRead(conversationID: Int, messageID: Int?) async {}
}

/// Emits no token: simulators without push, unconfigured Firebase, the fake server.
struct SilentTokenSource: PushTokenSource {
    func tokens() -> AsyncStream<String> {
        AsyncStream { _ in }
    }
}

/// Reports a fixed authorization and never shows the system prompt (UI tests, fake server).
struct StaticAuthorizer: NotificationAuthorizing {
    let status: NotificationAuthorization

    func currentAuthorization() async -> NotificationAuthorization { status }
    func request(_ request: AuthorizationRequest) async -> NotificationAuthorization { status }
}
