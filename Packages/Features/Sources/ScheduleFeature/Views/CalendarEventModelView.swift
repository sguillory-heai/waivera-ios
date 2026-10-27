#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Owns the model's tasks and turns its one-off requests into SwiftUI actions.
    struct CalendarEventModelView: View {
        let model: CalendarEventModel
        let onOpenConversation: (Int) -> Void

        @Environment(\.openURL) private var openURL

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
                    retry: { model.retry() }
                )
            )
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
            .waiveraHaptic(.selection, trigger: model.choiceTicks)
            .waiveraHaptic(.success, trigger: model.successTicks)
            .waiveraHaptic(.failure, trigger: model.failureTicks)
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
