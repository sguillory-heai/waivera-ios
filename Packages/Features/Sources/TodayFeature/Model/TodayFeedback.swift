import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// One-off results the screen shows as a toast, some with Retry or Undo.
enum TodayNotice: Hashable, Sendable {
    /// A refresh failed; cached data stays on screen.
    case refreshFailed
    /// The row went back to unread; Retry sends the mark-read again.
    case markReadFailed(activityId: Int64)
    case markAllFailed
    /// An invitation answer held for the Undo window (Android `OfferUndo`); `token` tells a
    /// later answer to the same invitation apart.
    case invitationAnswered(eventId: String, accept: Bool, token: Int)
    /// The invitation is back under Needs you; Retry sends the same answer again.
    case invitationFailed(eventId: String, accept: Bool)
    /// "Send wishes" could not open the chat; Retry tries again.
    case wishesFailed(userId: String)

    var message: String {
        switch self {
        case .refreshFailed: TodayStrings.text("today.toast.refreshFailed")
        case .markReadFailed: TodayStrings.text("today.toast.markReadFailed")
        case .markAllFailed: TodayStrings.text("today.toast.markAllFailed")
        case .invitationAnswered(_, let accept, _):
            TodayStrings.text(accept ? "today.toast.accepted" : "today.toast.declined")
        case .invitationFailed: TodayStrings.text("today.toast.invitationFailed")
        case .wishesFailed: TodayStrings.text("today.toast.wishesFailed")
        }
    }

    var offersRetry: Bool {
        switch self {
        case .invitationAnswered: false
        default: true
        }
    }

    var offersUndo: Bool {
        if case .invitationAnswered = self { return true }
        return false
    }
}

struct TodayToast: Identifiable, Hashable, Sendable {
    let id: UUID
    let notice: TodayNotice

    init(_ notice: TodayNotice, id: UUID = UUID()) {
        self.id = id
        self.notice = notice
    }
}

/// The toast on screen and the success and failure counters. Both are silent (haptics policy,
/// 2026-10-29); the toast says what happened.
@MainActor
@Observable
final class TodayFeedback {
    private(set) var toast: TodayToast?
    private(set) var successCount = 0
    private(set) var failureCount = 0

    func show(_ notice: TodayNotice) {
        // The same notice already on screen is not restarted, so four failed sources read as one.
        guard toast?.notice != notice else { return }
        toast = TodayToast(notice)
    }

    func succeed(_ notice: TodayNotice? = nil) {
        successCount += 1
        if let notice { show(notice) }
    }

    func fail(_ notice: TodayNotice) {
        failureCount += 1
        show(notice)
    }

    func dismiss(_ id: TodayToast.ID) {
        if toast?.id == id { toast = nil }
    }
}

/// Owns the short-lived tasks a screen starts for user actions (mark read, answer an
/// invitation). They finish even when the screen goes away, so a tap that navigates still
/// lands; they are cancelled when the owning model is released.
final class TaskBag: Sendable {
    private let tasks = LockedValue<[UUID: Task<Void, Never>]>([:])

    @MainActor
    func run(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        // The task body runs on the main actor after this method returns, so it is registered first.
        let task = Task { @MainActor [tasks] in
            await operation()
            tasks.update { _ = $0.removeValue(forKey: id) }
        }
        tasks.update { $0[id] = task }
    }

    var count: Int { tasks.get().count }

    func cancelAll() {
        let running = tasks.update { current -> [Task<Void, Never>] in
            defer { current.removeAll() }
            return Array(current.values)
        }
        for task in running { task.cancel() }
    }

    deinit { cancelAll() }
}

/// Drops a second navigation within `interval` of the first, so a fast double tap opens one
/// screen, not two (02 §6).
struct NavigationGuard {
    static let interval: TimeInterval = 0.6

    private var last: TimeInterval?

    mutating func allows(at uptime: TimeInterval) -> Bool {
        if let last, uptime - last < Self.interval { return false }
        last = uptime
        return true
    }
}

/// Reads the newest value of a replaying stream: every repository stream emits its current
/// value on subscription, so this returns at once.
func latest<Value: Sendable>(_ stream: AsyncStream<Value>) async -> Value? {
    for await value in stream { return value }
    return nil
}
