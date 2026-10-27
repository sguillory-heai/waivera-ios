import Foundation
import WaiveraAPI

#if canImport(Network)
    import Network
#endif

/// Whether the device has a usable network path.
public protocol ConnectivityMonitor: Sendable {
    /// Replays the current value.
    func isOnline() -> AsyncStream<Bool>
    var currentlyOnline: Bool { get }
}

/// Tests, previews and the fake server: online unless told otherwise.
public final class ManualConnectivity: ConnectivityMonitor {
    private let cell: StateCell<Bool>

    public init(online: Bool = true) {
        cell = StateCell(online)
    }

    public func isOnline() -> AsyncStream<Bool> { cell.stream() }
    public var currentlyOnline: Bool { cell.current }

    public func set(online: Bool) {
        guard cell.current != online else { return }
        cell.set(online)
    }
}

#if canImport(Network)
    /// `NWPathMonitor`-backed connectivity.
    public final class NetworkPathConnectivity: ConnectivityMonitor, @unchecked Sendable {
        // NWPathMonitor is only touched in init and deinit; its handler runs on its own queue.
        private let monitor = NWPathMonitor()
        private let cell = StateCell(true)

        public init() {
            let cell = cell
            monitor.pathUpdateHandler = { path in
                let online = path.status == .satisfied
                if cell.current != online { cell.set(online) }
            }
            monitor.start(queue: DispatchQueue(label: "com.waivera.connectivity"))
        }

        deinit {
            monitor.cancel()
        }

        public func isOnline() -> AsyncStream<Bool> { cell.stream() }
        public var currentlyOnline: Bool { cell.current }
    }
#endif
