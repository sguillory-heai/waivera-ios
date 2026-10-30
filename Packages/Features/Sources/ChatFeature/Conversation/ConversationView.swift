#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// One conversation. Scrolls to and highlights `targetMessageID` when given. A group's
    /// "N members" header line calls `onOpenMembers` with this conversation's id; the router
    /// pushes `GroupMembersView(channelID:)` for it (spec §9.2). Without it the line is plain text.
    public struct ConversationView: View {
        let conversationID: Int
        let targetMessageID: Int?
        let onOpenThread: (_ rootMessageID: Int, _ targetMessageID: Int?) -> Void
        let onOpenPerson: (_ userID: String) -> Void
        let onOpenMembers: ((_ conversationID: Int) -> Void)?

        @Environment(\.dataEnvironment) private var data
        @State private var model: ConversationModel?

        public init(
            conversationID: Int,
            targetMessageID: Int?,
            onOpenThread: @escaping (_ rootMessageID: Int, _ targetMessageID: Int?) -> Void,
            onOpenPerson: @escaping (_ userID: String) -> Void,
            onOpenMembers: ((_ conversationID: Int) -> Void)? = nil
        ) {
            self.conversationID = conversationID
            self.targetMessageID = targetMessageID
            self.onOpenThread = onOpenThread
            self.onOpenPerson = onOpenPerson
            self.onOpenMembers = onOpenMembers
        }

        public var body: some View {
            Group {
                if let model {
                    ConversationScreen(
                        model: model,
                        avatars: data?.avatars,
                        onOpenPerson: onOpenPerson,
                        onOpenMembers: onOpenMembers
                    )
                } else {
                    Palette.background.ignoresSafeArea()
                }
            }
            .task(id: conversationID) {
                let current = model?.conversationID == conversationID ? model : nil
                let active =
                    current
                    ?? ConversationModel(
                        conversationID: conversationID,
                        targetMessageID: targetMessageID,
                        data: data,
                        clock: data.map(ChatClock.employee) ?? ChatClock(),
                        platform: .live,
                        onOpenThread: { onOpenThread($0, $1) }
                    )
                model = active
                await active.run()
            }
        }
    }

    #if DEBUG
        #Preview("Light, demo data") {
            NavigationStack {
                ConversationView(
                    conversationID: 7,
                    targetMessageID: 9312,
                    onOpenThread: { _, _ in },
                    onOpenPerson: { _ in }
                )
            }
            .fakeDataEnvironment()
        }

        #Preview("Dark, demo data") {
            NavigationStack {
                ConversationView(
                    conversationID: 7,
                    targetMessageID: nil,
                    onOpenThread: { _, _ in },
                    onOpenPerson: { _ in }
                )
            }
            .fakeDataEnvironment()
            .preferredColorScheme(.dark)
        }

        #Preview("AX5, demo data") {
            NavigationStack {
                ConversationView(
                    conversationID: 7,
                    targetMessageID: nil,
                    onOpenThread: { _, _ in },
                    onOpenPerson: { _ in }
                )
            }
            .fakeDataEnvironment()
            .dynamicTypeSize(.accessibility5)
        }

        #Preview("Failing") {
            NavigationStack {
                ConversationView(
                    conversationID: 7,
                    targetMessageID: nil,
                    onOpenThread: { _, _ in },
                    onOpenPerson: { _ in }
                )
            }
            .fakeDataEnvironment(.failing)
        }
    #endif
#endif
