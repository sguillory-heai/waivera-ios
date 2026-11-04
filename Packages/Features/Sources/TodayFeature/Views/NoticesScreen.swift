#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct NoticesScreen: View {
        let model: NoticesModel
        let onOpen: (NoticeDestination) -> Void

        var body: some View {
            NoticesContent(
                state: model.state,
                actions: NoticesActions(
                    open: { id in
                        if let destination = model.open(id) { onOpen(destination) }
                    },
                    setFilter: { model.setFilter($0) },
                    markAllRead: { model.markAllRead() },
                    retry: { Task { await model.refresh() } }
                ),
                onRefresh: { [model] in await model.refresh() }
            )
            .todayFeedback(model.feedback, onAction: { model.retry($0) })
        }
    }
#endif
