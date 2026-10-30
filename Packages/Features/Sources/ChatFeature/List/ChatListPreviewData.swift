#if DEBUG
    import Foundation
    import WaiveraDesign

    /// Fixed rows for previews and snapshot tests, covering every row variant: unread direct,
    /// group with sender, channel with attachment, read-only archived channel, bot, typing,
    /// live call, a message that was not sent and a long title; plus the long-name set from the
    /// approved Android stills (wave 34 S1, `LongFixtures`).
    enum ChatListPreviewData {
        static let rows: [ChatRow] = [
            row(
                id: 63,
                title: "Priya Raman & 2 others",
                titleName: "Priya Raman",
                others: 2,
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
                typing: "Priya Raman is typing…",
                typingNamesEnd: 11
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
                id: 31,
                title: "Jordan Lee",
                leading: .direct(userId: "usr_jordan_lee", name: "Jordan Lee"),
                preview: "see you at 7",
                sender: "You",
                time: "Oct 19",
                sendFailed: true
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

        /// Wave 34 S1: a 60-character name, an unbroken 40-character name, a single letter, an
        /// emoji, a long typing name and a group whose count must survive.
        static let longNames: ChatListState = {
            let longest = "Maria-Fernanda Alejandra Castellanos-Rodriguez de la Vega"
            let unbroken = "Wolfeschlegelsteinhausenbergerdorffvoralt"
            let rows = [
                row(
                    id: 1,
                    title: longest,
                    leading: .direct(userId: "usr_mr", name: longest),
                    preview: "Can you cover Thursday?",
                    time: "4m"
                ),
                row(
                    id: 2,
                    title: unbroken,
                    leading: .direct(userId: "usr_w", name: unbroken),
                    preview: "Can you cover Thursday?",
                    time: "4m",
                    unread: 1,
                    typing: "\(unbroken) is typing…",
                    typingNamesEnd: unbroken.count
                ),
                row(
                    id: 3,
                    title: "Maximilianus Wolfeschlegelsteinhausen",
                    leading: .direct(userId: "usr_mw", name: "Maximilianus Wolfeschlegelsteinhausen"),
                    preview: "Can you cover Thursday?",
                    time: "4m",
                    unread: 2
                ),
                row(
                    id: 4,
                    title: "Q",
                    leading: .direct(userId: "usr_q", name: "Q"),
                    preview: "Can you cover Thursday?",
                    time: "4m",
                    unread: 3
                ),
                row(
                    id: 5,
                    title: "🌻",
                    leading: .direct(userId: "usr_sun", name: "🌻"),
                    preview: "Can you cover Thursday?",
                    time: "4m",
                    unread: 104
                ),
                row(
                    id: 6,
                    title: "M. Rui & 4 others",
                    titleName: "M. Rui",
                    others: 4,
                    leading: .group,
                    preview: "",
                    time: "Yesterday",
                    call: true
                ),
            ]
            return ChatListState(content: .rows, rows: rows, connection: .online)
        }()

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
            titleName: String? = nil,
            others: Int = 0,
            leading: RowLeading,
            preview: String,
            kind: PreviewKind = .text,
            sender: String? = nil,
            time: String,
            unread: Int = 0,
            typing: String? = nil,
            typingNamesEnd: Int? = nil,
            attachment: Bool = false,
            channel: Bool = false,
            readOnly: Bool = false,
            call: Bool = false,
            sendFailed: Bool = false
        ) -> ChatRow {
            ChatRow(
                id: id,
                title: title,
                titleName: titleName,
                titleCompactCount: others > 0 ? GroupTitle.compactSuffix(others: others) : nil,
                leading: leading,
                preview: preview,
                previewKind: kind,
                senderPrefix: sender,
                typingLabel: typing,
                typingNamesEnd: typingNamesEnd,
                timeLabel: time,
                unreadCount: unread,
                hasAttachment: attachment,
                isChannel: channel,
                isReadOnly: readOnly,
                isCallLive: call,
                isOpeningCall: false,
                arrivalKey: nil,
                isSendFailed: sendFailed,
                accessibilityText: [title, preview, time].filter { !$0.isEmpty }.joined(separator: ", ")
            )
        }
    }
#endif
