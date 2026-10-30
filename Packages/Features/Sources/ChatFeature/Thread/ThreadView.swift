#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// A thread under its root message. Joins the conversation's hub group.
    public struct ThreadView: View {
        let rootMessageID: Int
        let conversationID: Int?
        let targetMessageID: Int?
        let onOpenPerson: (_ userID: String) -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: ThreadModel?

        public init(
            rootMessageID: Int,
            conversationID: Int?,
            targetMessageID: Int?,
            onOpenPerson: @escaping (_ userID: String) -> Void
        ) {
            self.rootMessageID = rootMessageID
            self.conversationID = conversationID
            self.targetMessageID = targetMessageID
            self.onOpenPerson = onOpenPerson
        }

        public var body: some View {
            Group {
                if let model {
                    ThreadScreen(model: model, avatars: data?.avatars, onOpenPerson: onOpenPerson)
                } else {
                    Palette.background.ignoresSafeArea()
                }
            }
            .task(id: rootMessageID) {
                let current = model?.rootMessageID == rootMessageID ? model : nil
                let active =
                    current
                    ?? ThreadModel(
                        rootMessageID: rootMessageID,
                        conversationID: conversationID,
                        targetMessageID: targetMessageID,
                        data: data,
                        clock: data.map(ChatClock.employee) ?? ChatClock(),
                        platform: .live
                    )
                model = active
                await active.run()
            }
        }
    }

    #if DEBUG
        #Preview("Light, demo data") {
            NavigationStack {
                ThreadView(rootMessageID: 9330, conversationID: 7, targetMessageID: nil, onOpenPerson: { _ in })
            }
            .fakeDataEnvironment()
        }

        #Preview("Dark, demo data") {
            NavigationStack {
                ThreadView(rootMessageID: 9330, conversationID: 7, targetMessageID: nil, onOpenPerson: { _ in })
            }
            .fakeDataEnvironment()
            .preferredColorScheme(.dark)
        }

        #Preview("AX5, demo data") {
            NavigationStack {
                ThreadView(rootMessageID: 9330, conversationID: 7, targetMessageID: nil, onOpenPerson: { _ in })
            }
            .fakeDataEnvironment()
            .dynamicTypeSize(.accessibility5)
        }

        #Preview("Invalid route") {
            NavigationStack {
                ThreadView(rootMessageID: 9330, conversationID: nil, targetMessageID: nil, onOpenPerson: { _ in })
            }
            .fakeDataEnvironment()
        }
    #endif
#endif
