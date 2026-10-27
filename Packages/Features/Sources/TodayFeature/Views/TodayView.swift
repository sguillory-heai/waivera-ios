#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The Today tab root: what needs me now, the next three schedule items in my saved time
    /// zone, today's celebrations, then the activity feed. Opens from the cache, then refreshes.
    public struct TodayView: View {
        let onOpenConversation: (_ conversationID: Int, _ targetMessageID: Int?) -> Void
        let onOpenThread: (_ rootMessageID: Int, _ conversationID: Int?, _ targetMessageID: Int?) -> Void
        let onOpenEvent: (_ eventID: String) -> Void
        let onOpenSchedule: () -> Void
        let onOpenActivity: () -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: TodayModel?

        public init(
            onOpenConversation: @escaping (_ conversationID: Int, _ targetMessageID: Int?) -> Void,
            onOpenThread: @escaping (_ rootMessageID: Int, _ conversationID: Int?, _ targetMessageID: Int?) -> Void,
            onOpenEvent: @escaping (_ eventID: String) -> Void,
            onOpenSchedule: @escaping () -> Void,
            onOpenActivity: @escaping () -> Void
        ) {
            self.onOpenConversation = onOpenConversation
            self.onOpenThread = onOpenThread
            self.onOpenEvent = onOpenEvent
            self.onOpenSchedule = onOpenSchedule
            self.onOpenActivity = onOpenActivity
        }

        public var body: some View {
            Group {
                if let model {
                    TodayScreen(model: model, open: open)
                } else {
                    Palette.background
                }
            }
            .background(Palette.background)
            .navigationTitle(TodayStrings.text("today.title"))
            .task {
                let current = model ?? data.map { TodayModel(environment: $0, clock: TodayClock.resolve(for: $0)) }
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

    /// Binds the model to the stateless content, the toast and the haptics.
    private struct TodayScreen: View {
        let model: TodayModel
        let open: (TodayDestination) -> Void

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
                respond: { model.respond(toEventId: $0, accept: $1) },
                toggleNeedsYou: { model.toggleNeedsYouExpanded() },
                setFilter: { model.setFilter($0) },
                toggleUnreadOnly: { model.toggleUnreadOnly() },
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
            NavigationStack {
                TodayContent(state: TodayPreviewStates.populated(), actions: TodayActions(), onRefresh: {})
                    .navigationTitle(TodayStrings.text("today.title"))
            }
            .preferredColorScheme(.dark)
        }

        #Preview("AX XXXL, populated") {
            NavigationStack {
                TodayContent(state: TodayPreviewStates.populated(), actions: TodayActions(), onRefresh: {})
                    .navigationTitle(TodayStrings.text("today.title"))
            }
            .dynamicTypeSize(.accessibility5)
        }

        #Preview("All caught up") {
            NavigationStack {
                TodayContent(state: TodayPreviewStates.caughtUp(), actions: TodayActions(), onRefresh: {})
            }
        }

        #Preview("Offline, stale") {
            NavigationStack {
                TodayContent(state: TodayPreviewStates.offline(), actions: TodayActions(), onRefresh: {})
            }
            .preferredColorScheme(.dark)
        }

        #Preview("Error") {
            NavigationStack {
                TodayContent(state: TodayPreviewStates.failed(), actions: TodayActions(), onRefresh: {})
            }
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
