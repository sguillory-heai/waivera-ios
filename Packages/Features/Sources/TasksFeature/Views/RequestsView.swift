#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The Requests list on its own screen, for an approval notification or link, or the person's
    /// own requests (`mine`), which the Requests tab keeps behind one quiet row.
    public struct RequestsView: View {
        let onOpenTask: (_ taskID: Int) -> Void
        let onOpenMine: () -> Void
        let mine: Bool

        @Environment(\.dataEnvironment) private var data
        @State private var model: RequestsModel?

        public init(
            mine: Bool = false,
            onOpenTask: @escaping (_ taskID: Int) -> Void,
            onOpenMine: @escaping () -> Void = {}
        ) {
            self.mine = mine
            self.onOpenTask = onOpenTask
            self.onOpenMine = onOpenMine
        }

        private var title: String {
            TasksStrings.text(mine ? "tasks.requests.mine" : "tasks.segment.requests")
        }

        public var body: some View {
            Group {
                if let model {
                    RequestsScreen(
                        model: model,
                        onOpenTask: onOpenTask,
                        onOpenMine: onOpenMine,
                        mode: mine ? .mine : .waiting
                    )
                } else {
                    Palette.background
                }
            }
            .background(Palette.background)
            .navigationTitle(title)
            .waiveraTopBar(title)
            .task {
                if model == nil, let data { model = RequestsModel(environment: data) }
            }
        }
    }

    #if DEBUG
        #Preview("Requests") {
            NavigationStack { RequestsView(onOpenTask: { _ in }) }.fakeDataEnvironment()
        }
        #Preview("Requests dark") {
            NavigationStack { RequestsView(onOpenTask: { _ in }) }.fakeDataEnvironment().preferredColorScheme(.dark)
        }
        #Preview("Your requests") {
            NavigationStack { RequestsView(mine: true, onOpenTask: { _ in }) }.fakeDataEnvironment()
        }
        #Preview("Requests AX5") {
            NavigationStack { RequestsView(onOpenTask: { _ in }) }.fakeDataEnvironment()
                .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
