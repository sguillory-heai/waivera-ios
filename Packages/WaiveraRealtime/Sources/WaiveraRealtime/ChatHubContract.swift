/// Method and event names on sprout_api `ChatHub`, mapped at `api/chatHub`.
/// Keep in step with the hub and with the Android `ChatHubContract`.
public enum ChatHubContract {
    public static let path = "api/chatHub"

    /// Client-to-server hub methods.
    public enum Method {
        public static let joinConversation = "JoinConversation"
        public static let leaveConversation = "LeaveConversation"
        public static let sendMessage = "SendMessage"
        public static let sendTypingStatus = "SendTypingStatus"
        public static let markAsRead = "MarkAsRead"
        public static let sendReaction = "SendReaction"
    }

    /// Server-to-client events.
    public enum Event {
        public static let receiveMessage = "ReceiveMessage"
        public static let receiveConversationListMessage = "ReceiveConversationListMessage"
        public static let receiveTypingStatusForUser = "ReceiveTypingStatusForUser"
        public static let receiveReadReceipt = "ReceiveReadReceipt"
        public static let receiveReaction = "ReceiveReaction"
        public static let receiveBookmarkUpdate = "ReceiveBookmarkUpdate"
        public static let receiveChatActivity = "ReceiveChatActivity"
        public static let removeChatActivity = "RemoveChatActivity"
        public static let receiveChatReadState = "ReceiveChatReadState"
        public static let receiveChatAttention = "ReceiveChatAttention"
        public static let conversationCallStateChanged = "ConversationCallStateChanged"
    }
}
