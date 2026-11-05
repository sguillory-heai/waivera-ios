#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The Tasks tab root: Casework, My work and (for people the web shows Admin Requests to)
    /// Requests, under the hero bar. Casework and My work list open tasks by due group with a
    /// window, search, Assigned to me and the Delays choice; Requests reviews change requests.
    public struct TasksView: View {
        let onOpenTask: (_ taskID: Int) -> Void
        let onOpenMyRequests: () -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: TasksModel?
        @State private var requests: RequestsModel?

        public init(
            onOpenTask: @escaping (_ taskID: Int) -> Void,
            onOpenMyRequests: @escaping () -> Void = {}
        ) {
            self.onOpenTask = onOpenTask
            self.onOpenMyRequests = onOpenMyRequests
        }

        public var body: some View {
            ZStack {
                Palette.background.ignoresSafeArea()
                if let model, let requests {
                    TasksScreen(
                        model: model,
                        requests: requests,
                        onOpenTask: onOpenTask,
                        onOpenMyRequests: onOpenMyRequests
                    )
                }
            }
            .navigationTitle(TasksStrings.text("tasks.title"))
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if model == nil, let data {
                    model = TasksModel(environment: data)
                    requests = RequestsModel(environment: data)
                }
                await model?.run()
            }
        }
    }

    #if DEBUG
        #Preview("Light") {
            NavigationStack { TasksView(onOpenTask: { _ in }) }.fakeDataEnvironment()
        }
        #Preview("Dark") {
            NavigationStack { TasksView(onOpenTask: { _ in }) }.fakeDataEnvironment().preferredColorScheme(.dark)
        }
        #Preview("AX5") {
            NavigationStack { TasksView(onOpenTask: { _ in }) }.fakeDataEnvironment()
                .dynamicTypeSize(.accessibility5)
        }
        #Preview("Empty and failing") {
            TabView {
                NavigationStack { TasksView(onOpenTask: { _ in }) }.fakeDataEnvironment(.empty)
                    .tabItem { Text(verbatim: "empty") }
                NavigationStack { TasksView(onOpenTask: { _ in }) }.fakeDataEnvironment(.failing)
                    .tabItem { Text(verbatim: "failing") }
            }
        }
    #endif
#endif
