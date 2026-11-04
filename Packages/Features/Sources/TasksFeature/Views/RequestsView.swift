#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The Requests list on its own screen, for an approval notification or link.
    public struct RequestsView: View {
        let onOpenTask: (_ taskID: Int) -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: RequestsModel?

        public init(onOpenTask: @escaping (_ taskID: Int) -> Void) {
            self.onOpenTask = onOpenTask
        }

        public var body: some View {
            Group {
                if let model {
                    RequestsScreen(model: model, onOpenTask: onOpenTask)
                } else {
                    Palette.background
                }
            }
            .background(Palette.background)
            .navigationTitle(TasksStrings.text("tasks.segment.requests"))
            .waiveraTopBar(TasksStrings.text("tasks.segment.requests"))
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
        #Preview("Requests AX5") {
            NavigationStack { RequestsView(onOpenTask: { _ in }) }.fakeDataEnvironment()
                .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
