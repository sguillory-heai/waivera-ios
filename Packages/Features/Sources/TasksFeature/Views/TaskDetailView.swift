#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// One task: status and dates, who it is about, the pending request or active delay, the
    /// description and the activity, with Log activity and Ask for a change.
    public struct TaskDetailView: View {
        let taskID: Int
        let onOpenFile: (_ taskID: Int, _ attachmentID: Int) -> Void
        let onOpenTask: (_ taskID: Int) -> Void

        @Environment(\.dataEnvironment) private var data
        @Environment(\.openURL) private var openURL
        @State private var model: TaskDetailModel?

        /// `onOpenFile` pushes the read-only file viewer for a file the phone can show;
        /// `onOpenTask` pushes a related task that holds this one up.
        public init(
            taskID: Int,
            onOpenFile: @escaping (_ taskID: Int, _ attachmentID: Int) -> Void = { _, _ in },
            onOpenTask: @escaping (_ taskID: Int) -> Void = { _ in }
        ) {
            self.taskID = taskID
            self.onOpenFile = onOpenFile
            self.onOpenTask = onOpenTask
        }

        public var body: some View {
            Group {
                if let model {
                    TaskDetailScreen(model: model, onOpenFile: onOpenFile, onOpenTask: onOpenTask)
                } else {
                    Palette.background
                }
            }
            .background(Palette.background)
            .navigationTitle(title)
            .waiveraTopBar(title, subtitle: model?.state.task?.key, actions: barActions)
            .task {
                let current = model ?? data.map { TaskDetailModel(taskId: taskID, environment: $0) }
                if model == nil { model = current }
                await current?.run()
            }
        }

        /// Open on web sits in the bar, as on Android, once the task has loaded.
        private var barActions: [TopBarAction] {
            guard let model, model.state.task != nil else { return [] }
            return [
                TopBarAction(
                    id: "web",
                    systemImage: "arrow.up.right.square",
                    accessibilityLabel: TasksStrings.text("tasks.openOnWeb")
                ) {
                    if let url = model.webURL() { openURL(url) }
                }
            ]
        }

        private var title: String { model?.state.task?.title ?? TasksStrings.text("tasks.detail.title") }
    }

    #if DEBUG
        #Preview("Task") {
            NavigationStack { TaskDetailView(taskID: 12) }.fakeDataEnvironment()
        }
        #Preview("Task dark") {
            NavigationStack { TaskDetailView(taskID: 14) }.fakeDataEnvironment().preferredColorScheme(.dark)
        }
        #Preview("Task AX5") {
            NavigationStack { TaskDetailView(taskID: 12) }.fakeDataEnvironment().dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
