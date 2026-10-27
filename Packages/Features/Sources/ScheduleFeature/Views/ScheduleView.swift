#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The Schedule tab root: day, week and month calendar with the day agenda (07 §1–3).
    /// Everything is placed in the employee's saved zone; see `ScheduleModel`.
    public struct ScheduleView: View {
        let onOpenEvent: (_ eventID: String) -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: ScheduleModel?

        public init(
            onOpenEvent: @escaping (_ eventID: String) -> Void
        ) {
            self.onOpenEvent = onOpenEvent
        }

        public var body: some View {
            ZStack {
                Palette.background.ignoresSafeArea()
                if let model {
                    ScheduleModelView(model: model, onOpenEvent: onOpenEvent)
                }
            }
            .navigationTitle(ScheduleStrings.title)
            .navigationBarTitleDisplayMode(.large)
            .task {
                if model == nil, let data { model = ScheduleModel(data: data) }
            }
        }
    }

    #if DEBUG
        #Preview("Light") {
            NavigationStack { ScheduleView(onOpenEvent: { _ in }) }
                .fakeDataEnvironment()
        }
        #Preview("Dark") {
            NavigationStack { ScheduleView(onOpenEvent: { _ in }) }
                .fakeDataEnvironment()
                .preferredColorScheme(.dark)
        }
        #Preview("AX XXXL") {
            NavigationStack { ScheduleView(onOpenEvent: { _ in }) }
                .fakeDataEnvironment()
                .dynamicTypeSize(.accessibility5)
        }
        #Preview("States: empty, failing, slow") {
            TabView {
                NavigationStack { ScheduleView(onOpenEvent: { _ in }) }.fakeDataEnvironment(.empty)
                    .tabItem { Text(verbatim: "empty") }
                NavigationStack { ScheduleView(onOpenEvent: { _ in }) }.fakeDataEnvironment(.failing)
                    .tabItem { Text(verbatim: "failing") }
                NavigationStack { ScheduleView(onOpenEvent: { _ in }) }.fakeDataEnvironment(.slow)
                    .tabItem { Text(verbatim: "slow") }
            }
        }
        #Preview("Week, light and dark") {
            VStack {
                ScheduleScreenView(state: SchedulePreviewStates.schedule(.week))
                ScheduleScreenView(state: SchedulePreviewStates.schedule(.week)).environment(\.colorScheme, .dark)
            }
        }
    #endif
#endif
