#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// A participant's read-only profile (Android `ParticipantScreen`), opened from About on a
    /// client task: contact, plan dates, details and their open tasks.
    public struct ParticipantView: View {
        let participantID: Int
        let onOpenTask: (_ taskID: Int) -> Void

        @Environment(\.dataEnvironment) private var data
        @Environment(\.openURL) private var openURL
        @State private var model: ParticipantModel?

        public init(participantID: Int, onOpenTask: @escaping (_ taskID: Int) -> Void = { _ in }) {
            self.participantID = participantID
            self.onOpenTask = onOpenTask
        }

        public var body: some View {
            Group {
                if let model {
                    ParticipantContent(
                        state: model.state,
                        actions: ParticipantActions(
                            retry: { model.load() },
                            retryTasks: { model.loadTasks() },
                            openTask: onOpenTask,
                            contact: { url in
                                // A phone without a dialler or mail app says so instead of doing nothing.
                                openURL(url) { opened in
                                    guard !opened else { return }
                                    model.feedback.show(TasksStrings.text("tasks.participant.contactFailed"))
                                }
                            }
                        )
                    )
                    .tasksFeedback(model.feedback)
                } else {
                    Palette.background
                }
            }
            .background(Palette.background)
            .navigationTitle(TasksStrings.text("tasks.participant.title"))
            .waiveraTopBar(TasksStrings.text("tasks.participant.title"), actions: barActions)
            .task {
                guard model == nil, let data else { return }
                let created = ParticipantModel(participantId: participantID, environment: data)
                model = created
                created.load()
            }
        }

        /// Open on the web, except for a participant the viewer can't see.
        private var barActions: [TopBarAction] {
            guard let model, model.state.phase != .forbidden else { return [] }
            return [
                TopBarAction(
                    id: "web",
                    systemImage: "arrow.up.right.square",
                    accessibilityLabel: TasksStrings.text("tasks.participant.openWeb")
                ) {
                    if let url = model.webURL() { openURL(url) }
                }
            ]
        }
    }

    #if DEBUG
        #Preview("Participant") {
            NavigationStack { ParticipantView(participantID: 501) }.fakeDataEnvironment()
        }
        #Preview("Participant dark") {
            NavigationStack { ParticipantView(participantID: 502) }.fakeDataEnvironment().preferredColorScheme(.dark)
        }
        #Preview("Participant AX5") {
            NavigationStack { ParticipantView(participantID: 501) }
                .fakeDataEnvironment()
                .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
