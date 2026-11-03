#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The Schedule tab root: day, week and month calendar with the day agenda (07 §1–3), under
    /// the plum hero bar. Everything is placed in the employee's saved zone; see `ScheduleModel`.
    ///
    /// `onOpenAccount` shows the signed-in person's avatar in the hero bar (the account menu);
    /// `onOpenConversation` enables "Send wishes" on celebration cards. Both are optional so the
    /// shell can adopt them when it routes them.
    public struct ScheduleView: View {
        let onOpenEvent: (_ eventID: String) -> Void
        let onOpenConversation: ((_ conversationId: Int) -> Void)?
        let onOpenAccount: (() -> Void)?
        let focus: ScheduleFocusRequest?
        let onFocusHandled: () -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: ScheduleModel?
        @State private var avatar: Image?

        public init(
            onOpenEvent: @escaping (_ eventID: String) -> Void,
            onOpenConversation: ((_ conversationId: Int) -> Void)? = nil,
            onOpenAccount: (() -> Void)? = nil,
            focus: ScheduleFocusRequest? = nil,
            onFocusHandled: @escaping () -> Void = {}
        ) {
            self.onOpenEvent = onOpenEvent
            self.onOpenConversation = onOpenConversation
            self.onOpenAccount = onOpenAccount
            self.focus = focus
            self.onFocusHandled = onFocusHandled
        }

        public var body: some View {
            ZStack {
                Palette.background.ignoresSafeArea()
                if let model {
                    ScheduleModelView(
                        model: model,
                        account: account,
                        onOpenEvent: onOpenEvent,
                        onOpenConversation: onOpenConversation
                    )
                }
            }
            .navigationTitle(ScheduleStrings.title)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if model == nil, let data { model = ScheduleModel(data: data) }
                applyFocus()
                await loadAvatar()
            }
            .onChange(of: focus) { applyFocus() }
        }

        /// Applies a pending request from another tab once the model exists, then clears it.
        ///
        /// Without animation: the tab is switching at the same moment, and an animated swap of
        /// the grid then ran on SwiftUI's asynchronous renderer, which evaluated the grid's
        /// main-actor `ForEach` content off the main thread and crashed (TestFlight report,
        /// 2026-11-03: Today's "events today", Home, then "this week").
        private func applyFocus() {
            guard let focus, let model else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                switch focus.focus {
                case .today: model.showToday(in: .day)
                case .thisWeek: model.showToday(in: .week)
                }
            }
            onFocusHandled()
        }

        private var account: ScheduleAccount? {
            guard let onOpenAccount, let user = data?.session.currentState.user else { return nil }
            return ScheduleAccount(name: user.displayName ?? "", image: avatar, open: onOpenAccount)
        }

        private func loadAvatar() async {
            guard onOpenAccount != nil, let data, let id = data.session.currentState.user?.id,
                let bytes = await data.avatars.avatar(userId: id), let image = UIImage(data: bytes)
            else { return }
            avatar = Image(uiImage: image)
        }
    }

    #if DEBUG
        #Preview("Light") {
            NavigationStack { ScheduleView(onOpenEvent: { _ in }, onOpenConversation: { _ in }, onOpenAccount: {}) }
                .fakeDataEnvironment()
        }
        #Preview("Dark") {
            NavigationStack { ScheduleView(onOpenEvent: { _ in }, onOpenConversation: { _ in }, onOpenAccount: {}) }
                .fakeDataEnvironment()
                .preferredColorScheme(.dark)
        }
        #Preview("AX5") {
            NavigationStack { ScheduleView(onOpenEvent: { _ in }, onOpenConversation: { _ in }) }
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
        #Preview("Day timeline, light and dark") {
            VStack(spacing: 0) {
                ScheduleScreenView(state: SchedulePreviewStates.schedule(.day))
                ScheduleScreenView(state: SchedulePreviewStates.schedule(.day)).environment(\.colorScheme, .dark)
            }
        }
        #Preview("Week, AX5") {
            ScheduleScreenView(state: SchedulePreviewStates.schedule(.week))
                .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
