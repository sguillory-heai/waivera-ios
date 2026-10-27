#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// What the event screen can ask for. Main-actor closures, called from buttons only.
    public struct EventActions: Sendable {
        public var respond: @MainActor @Sendable (_ accept: Bool) -> Void
        public var retryResponse: @MainActor @Sendable () -> Void
        public var join: @MainActor @Sendable () -> Void
        public var dismissJoinError: @MainActor @Sendable () -> Void
        public var messageOrganizer: @MainActor @Sendable () -> Void
        public var retry: @MainActor @Sendable () -> Void

        public init(
            respond: @escaping @MainActor @Sendable (_ accept: Bool) -> Void = { _ in },
            retryResponse: @escaping @MainActor @Sendable () -> Void = {},
            join: @escaping @MainActor @Sendable () -> Void = {},
            dismissJoinError: @escaping @MainActor @Sendable () -> Void = {},
            messageOrganizer: @escaping @MainActor @Sendable () -> Void = {},
            retry: @escaping @MainActor @Sendable () -> Void = {}
        ) {
            self.respond = respond
            self.retryResponse = retryResponse
            self.join = join
            self.dismissJoinError = dismissJoinError
            self.messageOrganizer = messageOrganizer
            self.retry = retry
        }
    }
#endif
