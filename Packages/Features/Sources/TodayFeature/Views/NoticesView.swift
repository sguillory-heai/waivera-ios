#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The notifications inbox, the same list as the web bell: Tasks, Approvals and Meetings
    /// chips, day groups, Mark all read and the caught-up state. Rows open their task, request,
    /// event or web page and are marked read.
    public struct NoticesView: View {
        let onOpen: (NoticeDestination) -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: NoticesModel?

        public init(onOpen: @escaping (NoticeDestination) -> Void) {
            self.onOpen = onOpen
        }

        public var body: some View {
            Group {
                if let model {
                    NoticesScreen(model: model, onOpen: onOpen)
                } else {
                    Palette.background
                }
            }
            .background(Palette.background)
            .navigationTitle(TodayStrings.text("notices.title"))
            .waiveraTopBar(TodayStrings.text("notices.title"))
            .task {
                let current = model ?? data.map { NoticesModel(environment: $0, clock: $0.clock) }
                if model == nil { model = current }
                await current?.run()
            }
        }
    }

    #if DEBUG
        #Preview("Inbox, demo data") {
            NavigationStack { NoticesView(onOpen: { _ in }) }
                .fakeDataEnvironment()
        }

        #Preview("Inbox, dark") {
            NavigationStack { NoticesView(onOpen: { _ in }) }
                .fakeDataEnvironment()
                .preferredColorScheme(.dark)
        }

        #Preview("Inbox, AX XXXL") {
            NavigationStack { NoticesView(onOpen: { _ in }) }
                .fakeDataEnvironment()
                .dynamicTypeSize(.accessibility5)
        }

        #Preview("Inbox, empty") {
            NavigationStack { NoticesView(onOpen: { _ in }) }
                .fakeDataEnvironment(.empty)
        }
    #endif
#endif
