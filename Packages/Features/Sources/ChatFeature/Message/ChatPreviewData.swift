#if DEBUG
    import Foundation
    import WaiveraAPI
    import WaiveraData
    import WaiveraTestSupport

    /// The conversation screen states that previews and snapshot tests draw.
    enum ConversationPreviewVariant: String, CaseIterable, Sendable {
        case messages, loading, empty, error, reconnecting, readOnlyBot, typing, sendError, editing, liveCall
    }

    /// The thread screen states that previews and snapshot tests draw.
    enum ThreadPreviewVariant: String, CaseIterable, Sendable {
        case replies, loading, empty, error, readOnly
    }

    /// Fixed screen states built from the shared demo data with the same timeline rules the
    /// models use, so previews and snapshots show real rows without a running model.
    enum ChatPreviewData {
        static let conversationId = 7
        static let botConversationId = 90
        static let threadRootId = 9330
        static let editedMessageId = 9350

        /// The demo's fixed instant and zone, so relative times and day separators never drift.
        static var clock: ChatClock {
            ChatClock(clock: ManualClock(now: DemoData.now), timeZone: { DemoData.timeZone })
        }

        @MainActor
        static func conversationModel(_ variant: ConversationPreviewVariant) -> ConversationModel {
            ConversationModel(preview: conversation(variant), draft: draft(variant), clock: clock)
        }

        @MainActor
        static func threadModel(_ variant: ThreadPreviewVariant) -> ThreadModel {
            ThreadModel(preview: thread(variant), clock: clock)
        }

        static func conversation(_ variant: ConversationPreviewVariant) -> ConversationState {
            let demo = DemoData.make()
            var state = loaded(conversationId: variant == .readOnlyBot ? botConversationId : conversationId, demo: demo)
            switch variant {
            case .messages, .readOnlyBot: break
            case .loading, .error:
                state = ConversationState(title: state.title, content: variant == .error ? .error(.offline) : .loading)
            case .empty:
                state.items = []
                state.content = .empty
            case .reconnecting:
                state.subtitle = .reconnecting
                state.isStale = true
            case .typing: state.typing = otherName(state, demo: demo).map(TypingLabel.one) ?? .many
            case .sendError: state.sendError = .offline
            case .editing: state.editingMessageID = editedMessageId
            case .liveCall: state.call = CallDisplay(isAvailable: true, isLive: true)
            }
            return state
        }

        static func draft(_ variant: ConversationPreviewVariant) -> String {
            variant == .editing ? "Updated the shift notes for tomorrow" : ""
        }

        static func thread(_ variant: ThreadPreviewVariant) -> ThreadState {
            let demo = DemoData.make()
            var state = loadedThread(demo: demo)
            switch variant {
            case .replies: break
            case .loading: state = ThreadState(content: .loading, conversationTitle: state.conversationTitle)
            case .empty:
                state.replies = []
                state.replyCount = 0
            case .error: state = ThreadState(content: .error(.offline), conversationTitle: state.conversationTitle)
            case .readOnly:
                state.canWrite = false
                state.readOnlyReason = .readOnlyThread
            }
            return state
        }

        private static func loaded(conversationId: Int, demo: DemoData) -> ConversationState {
            let conversation = demo.conversations.first { $0.id == conversationId }
            let messages = (demo.messages[conversationId] ?? []).filter { !$0.isThreadReply }
            let isBot = conversation?.kind == .bot
            let sending = OutgoingMessage(
                clientMessageId: "preview-sending",
                conversationId: conversationId,
                parentMessageId: nil,
                text: "On my way",
                doc: nil,
                createdAt: DemoData.now,
                state: .sending
            )
            let pending = isBot ? [] : demo.pending.filter { $0.conversationId == conversationId } + [sending]
            let items = TimelineBuilder.build(
                TimelineInput(
                    messages: messages,
                    pending: pending,
                    viewerId: DemoData.viewerId,
                    zone: DemoData.timeZone,
                    botConversation: isBot
                )
            )
            var state = ConversationState(
                title: conversation?.title,
                content: items.isEmpty ? .empty : .messages,
                items: items,
                canWrite: !isBot,
                readOnlyReason: conversation.flatMap(ReadOnlyReason.conversation),
                call: CallDisplay(isAvailable: !isBot)
            )
            state.names = ChatNames.names(
                directory: demo.directory,
                participants: conversation?.participants ?? [],
                messages: messages
            )
            state.viewerId = DemoData.viewerId
            state.isBotConversation = isBot
            return state
        }

        private static func loadedThread(demo: DemoData) -> ThreadState {
            let thread = demo.threads[threadRootId]
            let conversation = demo.conversations.first { $0.id == conversationId }
            func build(_ messages: [ChatMessage], daySeparators: Bool = true) -> [TimelineItem] {
                TimelineBuilder.build(
                    TimelineInput(
                        messages: messages,
                        viewerId: DemoData.viewerId,
                        zone: DemoData.timeZone,
                        botConversation: false,
                        daySeparators: daySeparators
                    )
                )
            }
            let replies = thread?.replies ?? []
            var state = ThreadState(content: .ready, conversationTitle: conversation?.title, canWrite: true)
            if let root = thread?.root, case .message(let row) = build([root], daySeparators: false).first {
                state.root = row
            }
            state.replies = build(replies)
            state.replyCount = replies.count
            state.names = ChatNames.names(
                directory: demo.directory,
                participants: conversation?.participants ?? [],
                messages: [thread?.root].compactMap { $0 } + replies
            )
            state.viewerId = DemoData.viewerId
            return state
        }

        private static func otherName(_ state: ConversationState, demo: DemoData) -> String? {
            let conversation = demo.conversations.first { $0.id == conversationId }
            return conversation?.participants.first { $0.id != DemoData.viewerId }.flatMap { state.names[$0.id] }
        }
    }
#endif
