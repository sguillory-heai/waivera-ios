#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// The event screen drawn from plain state, so previews and snapshots render every state.
    public struct CalendarEventScreenView: View {
        let state: EventUIState
        let actions: EventActions

        public init(state: EventUIState, actions: EventActions = EventActions()) {
            self.state = state
            self.actions = actions
        }

        public var body: some View {
            LoadingContent(isLoading: state == .loading) {
                content
            } skeleton: {
                EventSkeleton()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.background)
        }

        @ViewBuilder private var content: some View {
            switch state {
            case .loading:
                EmptyView()
            case .notFound:
                EmptyStateView(
                    illustration: .schedule,
                    title: ScheduleStrings.text("schedule.event.notFound.title"),
                    message: ScheduleStrings.text("schedule.event.notFound.message")
                )
            case .error(let error):
                EmptyStateView.error(
                    title: ScheduleStrings.text("schedule.error.title"),
                    message: error.userMessage,
                    onRetry: { actions.retry() }
                )
            case .loaded(let details):
                ScrollView {
                    EventDetailsContent(details: details, actions: actions)
                        .padding(.horizontal, Spacing.medium)
                        .padding(.vertical, Spacing.medium)
                }
            }
        }
    }

    #if DEBUG
        #Preview("Invitation, light") {
            CalendarEventScreenView(state: SchedulePreviewStates.event(.pendingInvitation))
        }
        #Preview("Join open, dark") {
            CalendarEventScreenView(state: SchedulePreviewStates.event(.joinOpen))
                .preferredColorScheme(.dark)
        }
        #Preview("Failure, AX XXXL") {
            CalendarEventScreenView(state: SchedulePreviewStates.event(.responseFailed))
                .dynamicTypeSize(.accessibility5)
        }
        #Preview("Not found") {
            CalendarEventScreenView(state: SchedulePreviewStates.event(.notFound))
        }
    #endif
#endif
