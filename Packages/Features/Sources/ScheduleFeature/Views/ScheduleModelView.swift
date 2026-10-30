#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Connects the model's lifecycle to SwiftUI: the observation tasks are owned (and cancelled)
    /// by the view, "today" and the Now line move on every minute and when the app becomes active
    /// again, and a chat opened from "Send wishes" is followed once.
    struct ScheduleModelView: View {
        let model: ScheduleModel
        let account: ScheduleAccount?
        let onOpenEvent: (String) -> Void
        let onOpenConversation: ((Int) -> Void)?

        @Environment(\.scenePhase) private var scenePhase
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var preferredWeek = false

        private static let tickInterval: Duration = .seconds(60)

        var body: some View {
            ScheduleScreenView(
                state: model.state,
                actions: ScheduleActions(
                    selectView: { model.select(view: $0) },
                    selectDate: { model.select(date: $0) },
                    step: { model.step($0) },
                    goToToday: { model.goToToday() },
                    retry: { model.retry() },
                    retryMilestones: { model.retryMilestones() },
                    // Wrapped so the shell's callback, which is not Sendable, is never converted
                    // to the actions' Sendable function type (a strict-concurrency diagnostic).
                    openEvent: { onOpenEvent($0) },
                    sendWishes: { model.sendWishes(to: $0) }
                ),
                account: account,
                canSendWishes: model.canSendWishes && onOpenConversation != nil,
                refresh: { [model] in await model.refresh() }
            )
            .overlay(alignment: .bottom) { wishesSnackbar }
            .task { await model.start() }
            .task(id: model.feedKey) { await model.observeFeed() }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.tickInterval)
                    model.resume()
                }
            }
            .task(id: model.wishesFailure) {
                guard model.wishesFailure != nil else { return }
                let seconds = voiceOver ? FeedbackTiming.undoToastAccessible : FeedbackTiming.undoToast
                try? await Task.sleep(for: .seconds(seconds))
                if !Task.isCancelled { model.dismissWishesFailure() }
            }
            .onChange(of: model.wishesRequest) { _, request in
                guard let request else { return }
                onOpenConversation?(request.conversationId)
                model.wishesHandled(request)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.resume() }
            }
            .onAppear(perform: preferWeekAtLargestText)
        }

        /// At the largest text sizes a month grid fills the first screen, so the first time the
        /// tab shows Month at that size it switches to the week strip. Picking Month again sticks.
        private func preferWeekAtLargestText() {
            guard !preferredWeek else { return }
            preferredWeek = true
            if dynamicTypeSize.isExtraLargeText, model.view == .month { model.select(view: .week) }
        }

        @ViewBuilder private var wishesSnackbar: some View {
            ZStack {
                if let failure = model.wishesFailure {
                    SnackbarView(
                        message: ScheduleStrings.text("schedule.wishesFailed"),
                        actionTitle: ScheduleStrings.text("schedule.retry"),
                        action: { model.sendWishes(to: failure.userId) }
                    )
                    .padding(Spacing.gutter)
                    .transition(Motion.transition(edge: .bottom, reduceMotion: reduceMotion))
                }
            }
            .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: model.wishesFailure)
        }
    }
#endif
