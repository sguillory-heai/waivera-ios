#if DEBUG
    import Foundation

    /// Fixed rows for previews and snapshot tests, covering every row variant: unread direct,
    /// group with sender, channel with attachment, read-only archived channel, bot, typing,
    /// live call and a long title.
    enum ChatListPreviewData {
        static let rows: [ChatRow] = [
            row(
                id: 63,
                title: "Priya Raman & 2 others",
                leading: .group,
                preview: "Van 2 is back at the office",
                sender: "Jordan",
                time: "20m",
                unread: 2
            ),
            row(
                id: 90,
                title: "Waivera",
                leading: .bot,
                preview: "Ticket T-1042 updated",
                time: "50m",
                unread: 1
            ),
            row(
                id: 7,
                title: "Priya Raman",
                leading: .direct(userId: "usr_priya_raman", name: "Priya Raman"),
                preview: "can you cover Friday?",
                sender: "You",
                time: "Oct 20",
                typing: "Priya Raman is typing…"
            ),
            row(
                id: 41,
                title: "north-team",
                leading: .channel(archived: false),
                preview: "roster.pdf",
                kind: .attachment,
                sender: "Jordan",
                time: "Oct 20",
                unread: 3,
                attachment: true,
                channel: true
            ),
            row(
                id: 12,
                title: "Sam Ortiz",
                leading: .direct(userId: "usr_sam_ortiz", name: "Sam Ortiz"),
                preview: "",
                time: "Yesterday",
                call: true
            ),
            row(
                id: 58,
                title: "old-pilot",
                leading: .channel(archived: true),
                preview: "No messages yet",
                kind: .placeholder,
                time: "",
                channel: true,
                readOnly: true
            ),
            row(
                id: 77,
                title: "Operations, maintenance and weekend coverage for the north depot",
                leading: .channel(archived: false),
                preview: "Conversation update",
                kind: .system,
                time: "Oct 2",
                channel: true
            ),
        ]

        static var state: ChatListState {
            ChatListState(content: .rows, rows: rows, connection: .online)
        }

        static func state(_ content: ChatListContent, connection: ConnectionIndicator = .online) -> ChatListState {
            ChatListState(content: content, rows: [], connection: connection)
        }

        // swiftlint:disable:next function_parameter_count
        private static func row(
            id: Int,
            title: String,
            leading: RowLeading,
            preview: String,
            kind: PreviewKind = .text,
            sender: String? = nil,
            time: String,
            unread: Int = 0,
            typing: String? = nil,
            attachment: Bool = false,
            channel: Bool = false,
            readOnly: Bool = false,
            call: Bool = false
        ) -> ChatRow {
            ChatRow(
                id: id,
                title: title,
                leading: leading,
                preview: preview,
                previewKind: kind,
                senderPrefix: sender,
                typingLabel: typing,
                timeLabel: time,
                unreadCount: unread,
                hasAttachment: attachment,
                isChannel: channel,
                isReadOnly: readOnly,
                isCallLive: call,
                isOpeningCall: false,
                arrivalKey: nil,
                accessibilityText: [title, preview, time].filter { !$0.isEmpty }.joined(separator: ", ")
            )
        }
    }
#endif
