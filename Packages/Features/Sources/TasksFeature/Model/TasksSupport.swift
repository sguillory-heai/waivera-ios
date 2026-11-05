import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// A section that loads on its own, so a screen shows while one part is still coming.
enum Loadable<Value: Sendable & Equatable>: Equatable, Sendable {
    case loading
    case failed
    case ready(Value)

    var value: Value? {
        if case .ready(let value) = self { return value }
        return nil
    }

    func map<Other: Sendable & Equatable>(_ transform: (Value) -> Other) -> Loadable<Other> {
        switch self {
        case .loading: .loading
        case .failed: .failed
        case .ready(let value): .ready(transform(value))
        }
    }
}

/// One-off results a Tasks screen shows as a toast. Haptics stay silent; the toast says it.
struct TasksToast: Identifiable, Hashable, Sendable {
    let id: UUID
    let message: String
    /// Shown as Try again; nil for a toast with no action.
    let retry: TasksRetry?

    init(_ message: String, retry: TasksRetry? = nil, id: UUID = UUID()) {
        self.id = id
        self.message = message
        self.retry = retry
    }
}

enum TasksRetry: Hashable, Sendable {
    case refresh
}

@MainActor
@Observable
final class TasksFeedback {
    private(set) var toast: TasksToast?

    func show(_ message: String, retry: TasksRetry? = nil) {
        guard toast?.message != message else { return }
        toast = TasksToast(message, retry: retry)
    }

    func dismiss(_ id: TasksToast.ID) {
        if toast?.id == id { toast = nil }
    }
}

/// Owns the short-lived tasks a screen starts for user actions. They finish even when the
/// screen goes away, so a tap that navigates still lands; they stop with the owning model.
final class TaskBag: Sendable {
    private let tasks = LockedValue<[UUID: Task<Void, Never>]>([:])

    @MainActor
    func run(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        let task = Task { @MainActor [tasks] in
            await operation()
            tasks.update { _ = $0.removeValue(forKey: id) }
        }
        tasks.update { $0[id] = task }
    }

    /// Runs `operation` in place of the task last started under `key`, cancelling that one; the
    /// operation checks `Task.isCancelled` before it writes, so the last one asked for wins.
    @MainActor
    @discardableResult
    func replace(_ key: String, _ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let id = UUID()
        let task = Task { @MainActor [tasks] in
            await operation()
            tasks.update { _ = $0.removeValue(forKey: id) }
        }
        let previous = keyed.update { current -> UUID? in
            defer { current[key] = id }
            return current[key]
        }
        tasks.update { current in
            if let previous { current.removeValue(forKey: previous)?.cancel() }
            current[id] = task
        }
        return task
    }

    private let keyed = LockedValue<[String: UUID]>([:])

    /// Cancels the task last started under `key`, if it is still running.
    func cancel(_ key: String) {
        guard let id = keyed.update({ $0.removeValue(forKey: key) }) else { return }
        tasks.update { $0.removeValue(forKey: id)?.cancel() }
    }

    func cancelAll() {
        let running = tasks.update { current -> [Task<Void, Never>] in
            defer { current.removeAll() }
            return Array(current.values)
        }
        for task in running { task.cancel() }
    }

    deinit { cancelAll() }
}

/// Drops a second navigation within 600 ms of the first, so a fast double tap opens one screen.
struct NavigationGuard {
    static let interval: TimeInterval = 0.6

    private var last: TimeInterval?

    mutating func allows(at uptime: TimeInterval) -> Bool {
        if let last, uptime - last < Self.interval { return false }
        last = uptime
        return true
    }
}

/// A web page for something the phone has no screen for, only on the configured web host.
enum TasksWeb {
    static func url(_ path: String, base: URL?) -> URL? { WebAddress.page(path, on: base) }
}
