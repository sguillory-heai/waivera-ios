/// Method and event names on sprout_api `ChatHub` (`api/chatHub`) and `VideoHub`
/// (`api/videoHub`), from `spec/contract/hub.md`. Keep in step with the Android contract.
public enum ChatHubContract {
    public static let path = "api/chatHub"

    /// Client-to-server hub methods the staff app calls.
    public enum Method {
        public static let joinConversation = "JoinConversation"
        public static let leaveConversation = "LeaveConversation"
        public static let sendMessage = "SendMessage"
        public static let sendTypingStatus = "SendTypingStatus"
        public static let markAsRead = "MarkAsRead"
        public static let sendReaction = "SendReaction"
        public static let getConnectionId = "GetConnectionId"
        public static let getUserIdentifier = "GetUserIdentifier"
        /// Phase-2 task comments.
        public static let sendTaskMessage = "SendTaskMessage"
    }

    /// Server-to-client events. Every name the server can send is registered, even as a
    /// no-op, so the client never logs unhandled-method warnings (11 §3.43). The phantom
    /// names the Expo client registers (`NewMessage`, `ReceiveTypingStatus`, …) are not here.
    public enum Event {
        public static let receiveMessage = "ReceiveMessage"
        public static let receiveConversationListMessage = "ReceiveConversationListMessage"
        public static let receiveChatAttention = "ReceiveChatAttention"
        public static let receiveChatActivity = "ReceiveChatActivity"
        public static let removeChatActivity = "RemoveChatActivity"
        public static let receiveChatReadState = "ReceiveChatReadState"
        public static let receiveTypingStatusForUser = "ReceiveTypingStatusForUser"
        public static let receiveReadReceipt = "ReceiveReadReceipt"
        public static let receiveReaction = "ReceiveReaction"
        public static let receiveBookmarkUpdate = "ReceiveBookmarkUpdate"
        public static let receiveMessageUpdate = "ReceiveMessageUpdate"
        public static let receiveMessageDelete = "ReceiveMessageDelete"
        public static let conversationCreated = "ConversationCreated"
        public static let conversationCallStateChanged = "ConversationCallStateChanged"
        public static let removeAdHocFromConversation = "RemoveAdHocFromConversation"
        public static let receiveNotification = "ReceiveNotification"
        /// Lower-cased on the server; registered verbatim.
        public static let receiveNotificationWeb = "receivenotification_web"
        public static let receiveComment = "ReceiveComment"

        /// Each event with the kind of every positional argument, so a transport can bind
        /// handlers without knowing the payload types.
        public static let signatures: [String: [HubArgumentKind]] = [
            receiveMessage: [.object],
            receiveConversationListMessage: [.object],
            receiveChatAttention: [.object, .primitive],
            receiveChatActivity: [.object],
            removeChatActivity: [.primitive],
            receiveChatReadState: [.object],
            receiveTypingStatusForUser: [.primitive, .primitive, .primitive],
            receiveReadReceipt: [.primitive, .primitive, .primitive],
            receiveReaction: [.primitive, .primitive, .primitive, .primitive, .primitive],
            receiveBookmarkUpdate: [.object],
            receiveMessageUpdate: [.object],
            receiveMessageDelete: [.object],
            conversationCreated: [.object],
            conversationCallStateChanged: [.object],
            removeAdHocFromConversation: [.object],
            receiveNotification: [.object],
            receiveNotificationWeb: [.object],
            receiveComment: [.object],
        ]
    }
}

/// Whether a positional hub argument is a JSON object/array or a scalar (number, string,
/// bool, null). SignalR clients bind the two differently.
public enum HubArgumentKind: Sendable, Equatable {
    case object
    case primitive
}

/// `VideoHub` names the chat features need (hub.md §4). Phase 1 only renders call state from
/// the chat hub; these are here so a video connection can reuse the same transport.
public enum VideoHubContract {
    public static let path = "api/videoHub"

    public enum Method {
        public static let joinRoom = "JoinRoom"
        public static let leaveRoom = "LeaveRoom"
        public static let rejectCall = "RejectCall"
        public static let notifyUserLeft = "NotifyUserLeft"
        public static let notifyCallRingingOffToUsers = "NotifyCallRingingOffToUsers"
    }

    public enum Event {
        public static let receiveGroupCallInvite = "ReceiveGroupCallInvite"
        public static let receiveExternalGroupCallInvite = "ReceiveExternalGroupCallInvite"
        public static let newPublisher = "NewPublisher"
        public static let existingParticipants = "ExistingParticipants"
        public static let remoteMediaStateChanged = "RemoteMediaStateChanged"
        public static let remoteFeedLeft = "RemoteFeedLeft"
        public static let screenShareStarted = "ScreenShareStarted"
        public static let screenShareEnded = "ScreenShareEnded"
        public static let callRejected = "CallRejected"

        public static let signatures: [String: [HubArgumentKind]] = [
            receiveGroupCallInvite: [.object],
            receiveExternalGroupCallInvite: [.object],
            newPublisher: [.object],
            existingParticipants: [.object],
            remoteMediaStateChanged: [.object],
            remoteFeedLeft: [.object],
            screenShareStarted: [.object],
            screenShareEnded: [.object],
            callRejected: [.object],
        ]
    }
}
