#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The Today tab root: the plum hero (greeting, what needs me, the count-only ring, stats),
    /// then what needs me now, my day, the next schedule items in my saved time zone, today's
    /// celebrations and the activity feed. Opens from the cache, then refreshes. The hero draws
    /// its own bar, so the navigation bar is hidden here.
    public struct TodayView: View {
        let onOpenConversation: (_ conversationID: Int, _ targetMessageID: Int?) -> Void
        let onOpenThread: (_ rootMessageID: Int, _ conversationID: Int?, _ targetMessageID: Int?) -> Void
        let onOpenEvent: (_ eventID: String) -> Void
        let onOpenSchedule: () -> Void
        let onOpenActivity: () -> Void
        let onOpenAccount: (() -> Void)?

        @Environment(\.dataEnvironment) private var data
        @State private var model: TodayModel?

        public init(
            onOpenConversation: @escaping (_ conversationID: Int, _ targetMessageID: Int?) -> Void,
            onOpenThread: @escaping (_ rootMessageID: Int, _ conversationID: Int?, _ targetMessageID: Int?) -> Void,
            onOpenEvent: @escaping (_ eventID: String) -> Void,
            onOpenSchedule: @escaping () -> Void,
            onOpenActivity: @escaping () -> Void,
            onOpenAccount: (() -> Void)? = nil
        ) {
            self.onOpenConversation = onOpenConversation
            self.onOpenThread = onOpenThread
            self.onOpenEvent = onOpenEvent
            self.onOpenSchedule = onOpenSchedule
            self.onOpenActivity = onOpenActivity
            self.onOpenAccount = onOpenAccount
        }

        public var body: some View {
            Group {
                if let model {
                    TodayScreen(model: model, open: open, openAccount: onOpenAccount)
                } else {
                    Palette.background
                }
            }
            .background(Palette.background)
            .navigationTitle(TodayStrings.text("today.title"))
            .toolbar(.hidden, for: .navigationBar)
            .task {
                let current = model ?? data.map { TodayModel(environment: $0, clock: $0.clock) }
                if model == nil { model = current }
                await current?.run()
            }
        }

        /// Maps a Today destination to the router closure for it. Threads open by their root id.
        private func open(_ destination: TodayDestination) {
            switch destination {
            case .chat(.conversation(let id, let target)): onOpenConversation(id, target)
            case .chat(.thread(let root, let conversation, let target)): onOpenThread(root, conversation, target)
            case .event(let id): onOpenEvent(id)
            case .schedule: onOpenSchedule()
            case .activity: onOpenActivity()
            }
        }
    }

    /// Binds the model to the stateless content and the toast.
    private struct TodayScreen: View {
        let model: TodayModel
        let open: (TodayDestination) -> Void
        let openAccount: (() -> Void)?

        var body: some View {
            TodayContent(state: model.state, actions: actions, onRefresh: { [model] in await model.refresh() })
                .todayFeedback(model.feedback) { model.retry($0) }
        }

        private var actions: TodayActions {
            TodayActions(
                reload: { model.retry(TodayToast(.refreshFailed)) },
                open: { destination, activityId in
                    if let allowed = model.navigate(to: destination, markingRead: activityId) { open(allowed) }
                },
                openAccount: openAccount,
                respond: { model.respond(toEventId: $0, accept: $1) },
                toggleNeedsYou: { model.toggleNeedsYouExpanded() },
                setFilter: { model.setFilter($0) },
                toggleUnreadOnly: { model.toggleUnreadOnly() },
                clearFilters: { model.clearActivityFilters() },
                markRead: { model.markRead($0) },
                markAllRead: { model.markAllRead() },
                loadMore: { model.loadMoreActivity() },
                retryMore: { model.retryMoreActivity() }
            )
        }
    }

    #if DEBUG
        #Preview("Light, demo data") {
            NavigationStack {
                TodayView(
                    onOpenConversation: { _, _ in },
                    onOpenThread: { _, _, _ in },
                    onOpenEvent: { _ in },
                    onOpenSchedule: {},
                    onOpenActivity: {}
                )
            }
            .fakeDataEnvironment()
        }

        #Preview("Dark, populated") {
            TodayContent(state: TodayPreviewStates.populated(), actions: TodayActions(), onRefresh: {})
                .preferredColorScheme(.dark)
        }

        #Preview("AX5, long content") {
            TodayContent(state: TodayPreviewStates.longContent(), actions: TodayActions(), onRefresh: {})
                .dynamicTypeSize(.accessibility5)
        }

        #Preview("All caught up, long name") {
            TodayContent(state: TodayPreviewStates.caughtUpLongName(), actions: TodayActions(), onRefresh: {})
        }

        #Preview("Loading") {
            TodayContent(state: TodayPreviewStates.loading(), actions: TodayActions(), onRefresh: {})
        }

        #Preview("Offline, stale") {
            TodayContent(state: TodayPreviewStates.offline(), actions: TodayActions(), onRefresh: {})
                .preferredColorScheme(.dark)
        }

        #Preview("Error") {
            TodayContent(state: TodayPreviewStates.failed(), actions: TodayActions(), onRefresh: {})
        }

        #Preview("Failing scenario") {
            NavigationStack {
                TodayView(
                    onOpenConversation: { _, _ in },
                    onOpenThread: { _, _, _ in },
                    onOpenEvent: { _ in },
                    onOpenSchedule: {},
                    onOpenActivity: {}
                )
            }
            .fakeDataEnvironment(.failing)
        }
    #endif
#endif
