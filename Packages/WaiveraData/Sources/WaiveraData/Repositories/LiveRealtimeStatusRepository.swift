import Foundation
import WaiveraAPI
import WaiveraRealtime

/// Folds hub status and connectivity into the quiet banner (05 §2).
public final class LiveRealtimeStatusRepository: RealtimeStatusRepository {
    private let realtime: any RealtimeClient
    private let connectivity: any ConnectivityMonitor
    private let cell = StateCell(ConnectionBanner.hidden)
    private let tasks = LockedValue<[Task<Void, Never>]>([])

    public init(realtime: any RealtimeClient, connectivity: any ConnectivityMonitor) {
        self.realtime = realtime
        self.connectivity = connectivity
        let statuses = realtime.statuses()
        let online = connectivity.isOnline()
        let cell = cell
        let latest = LockedValue((status: realtime.currentStatus, online: connectivity.currentlyOnline))
        let publish: @Sendable () -> Void = {
            let value = latest.get()
            let banner = Self.banner(status: value.status, online: value.online)
            if cell.current != banner { cell.set(banner) }
        }
        tasks.update {
            $0 = [
                Task {
                    for await status in statuses {
                        latest.update { $0.status = status }
                        publish()
                    }
                },
                Task {
                    for await isOnline in online {
                        latest.update { $0.online = isOnline }
                        publish()
                    }
                },
            ]
        }
    }

    deinit {
        for task in tasks.get() { task.cancel() }
    }

    static func banner(status: RealtimeStatus, online: Bool) -> ConnectionBanner {
        guard online else { return .offline }
        switch status.state {
        case .connected, .disconnected: return .hidden
        case .connecting: return status.epoch == 0 ? .connecting : .reconnecting(attempt: 1)
        case .reconnecting(let attempt, _): return .reconnecting(attempt: attempt)
        }
    }

    public func banner() -> AsyncStream<ConnectionBanner> { cell.stream() }
    public func statuses() -> AsyncStream<RealtimeStatus> { realtime.statuses() }
    public func retryNow() async { await realtime.retryNow() }
}
