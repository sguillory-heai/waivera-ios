#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Owns the model's tasks and turns its one-off requests into SwiftUI actions.
    struct CalendarEventModelView: View {
        let model: CalendarEventModel
        let onOpenConversation: (Int) -> Void

        @Environment(\.openURL) private var openURL
        @Environment(\.dismiss) private var dismiss
        @Environment(\.dataEnvironment) private var data
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
        @State private var form: EventFormModel?
        @State private var confirmingCancel = false
        @State private var savedMessage: EventSaved?

        /// How often the join window and "has started" state are re-evaluated.
        private static let tickInterval: Duration = .seconds(30)

        var body: some View {
            CalendarEventScreenView(
                state: model.state,
                actions: EventActions(
                    respond: { model.respond(accept: $0) },
                    retryResponse: { model.retryResponse() },
                    join: { model.join() },
                    dismissJoinError: { model.dismissJoinError() },
                    messageOrganizer: { model.messageOrganizer() },
                    retry: { model.retry() },
                    edit: { openEditor() },
                    cancelEvent: { confirmingCancel = true },
                    editOnWeb: editOnWeb,
                    dismissCancelFailure: { model.dismissCancelFailure() }
                )
            )
            .overlay(alignment: .bottom) { savedSnackbar }
            .sheet(item: $form) { form in
                EventFormSheet(
                    model: form,
                    onClose: { self.form = nil },
                    onSaved: { saved in
                        self.form = nil
                        savedMessage = saved
                    }
                )
            }
            .sheet(isPresented: $confirmingCancel) {
                ConfirmationSheet(
                    title: ScheduleStrings.text("schedule.cancel.title"),
                    message: ScheduleStrings.text("schedule.cancel.message"),
                    confirmTitle: ScheduleStrings.text("schedule.cancel.confirm"),
                    cancelTitle: ScheduleStrings.text("schedule.cancel.keep"),
                    onConfirm: { model.cancelEvent() }
                )
                .waiveraFittedSheetPresentation()
            }
            .onChange(of: model.closeRequest) { _, request in
                guard request != nil else { return }
                model.closeHandled()
                dismiss()
            }
            .task(id: savedMessage) {
                guard let message = savedMessage else { return }
                AccessibilityNotification.Announcement(message.message).post()
                let seconds = voiceOver ? FeedbackTiming.undoToastAccessible : FeedbackTiming.undoToast
                try? await Task.sleep(for: .seconds(seconds))
                if !Task.isCancelled, savedMessage == message { savedMessage = nil }
            }
            .undoToast(item: toastItem) { item in
                if let offer = model.undoOffer, offer.id == item.id { model.undo(offer) }
            }
            .task { await model.observe() }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.tickInterval)
                    model.tick()
                }
            }
            .onChange(of: model.openRequest) { _, request in
                guard let request else { return }
                openURL(request.url) { accepted in model.linkHandled(request, accepted: accepted) }
            }
            .onChange(of: model.conversationRequest) { _, request in
                guard let request else { return }
                onOpenConversation(request.conversationId)
                model.conversationHandled(request)
            }
            .onDisappear { model.disappear() }
        }

        private var editOnWeb: (@MainActor @Sendable () -> Void)? {
            guard let url = model.webCalendarURL else { return nil }
            let openURL = openURL
            return { openURL(url) }
        }

        private func openEditor() {
            guard let event = model.editableEvent, let data else { return }
            form = EventFormModel(event: event, data: data)
        }

        @ViewBuilder private var savedSnackbar: some View {
            ZStack {
                if let savedMessage {
                    SnackbarView(message: savedMessage.message)
                        .padding(Spacing.gutter)
                        .transition(Motion.transition(edge: .bottom, reduceMotion: reduceMotion))
                }
            }
            .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: savedMessage)
        }

        /// The toast shows the model's current offer. When the toast times out (or is replaced)
        /// the answer is sent at once instead of waiting out the rest of the model's window.
        private var toastItem: Binding<UndoToastItem?> {
            Binding(
                get: { model.undoOffer.map { UndoToastItem(id: $0.id, message: $0.message) } },
                set: { item in
                    if item == nil, let offer = model.undoOffer { model.undoDismissed(offer) }
                }
            )
        }
    }
#endif
