#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// One inbox row: leading tile or avatar, the one-line name and time, then the preview with
    /// its sender prefix (or the call, "Not sent" or typing line in its place) and the unread
    /// count. Unread is two signals only: the ExtraBold name and the rose count, which VoiceOver
    /// reads as "N unread". No row wash, presence dot or coloured time on top (Android
    /// `ConversationRow`). The list owns the press, swipe actions and the actions sheet.
    struct ConversationRowView: View {
        let row: ChatRow
        let avatar: Image?
        let onJoinCall: () -> Void

        @Environment(\.dynamicTypeSize) private var typeSize

        var body: some View {
            HStack(alignment: .top, spacing: Spacing.mediumSmall) {
                RowLeadingView(leading: row.leading, avatar: avatar)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    HStack(alignment: .center, spacing: Spacing.extraSmall) {
                        ChatRowTitle(row: row)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if row.isReadOnly {
                            Image(systemName: "lock.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: ControlSize.iconSmall, height: ControlSize.iconSmall)
                                .foregroundStyle(Palette.textSecondary)
                                .accessibilityHidden(true)
                        }
                        if !row.timeLabel.isEmpty {
                            Text(row.timeLabel)
                                .waiveraTextStyle(.labelSmall)
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        if callOwnLine { CountBadge(count: row.unreadCount) }
                    }
                    HStack(alignment: .center, spacing: Spacing.small) {
                        subtitle
                            .frame(maxWidth: .infinity, alignment: .leading)
                        // Always in the tree, so marking the row read shrinks the count away.
                        if !callOwnLine { CountBadge(count: row.unreadCount) }
                    }
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.mediumSmall)
            .frame(maxWidth: .infinity, minHeight: ControlSize.listRowMinHeight, alignment: .topLeading)
        }

        /// At large text a live call's pill gets the text column to itself and the count moves up
        /// beside the time, so "Join call" never loses its verb to the badge (Android UI10-03).
        private var callOwnLine: Bool { row.isCallLive && typeSize.isLargeText }

        @ViewBuilder private var subtitle: some View {
            if row.isCallLive {
                CallJoinButton(isOpening: row.isOpeningCall, action: onJoinCall)
            } else if row.isSendFailed {
                NotSentLine()
            } else if let typing = row.typingLabel {
                TypingPreviewLine(full: typing, parts: row.typingParts)
            } else {
                PreviewLine(row: row)
            }
        }
    }

    /// A chat's name on one line: it shrinks to 85%, then ends in "…". A group keeps
    /// "& N others" and cuts only the name, then falls back to "Name… +N" (v7 items 3 and 4).
    struct ChatRowTitle: View {
        let row: ChatRow

        var body: some View {
            let weight: FontWeightToken = row.isUnread ? .extraBold : .semibold
            Group {
                if let name = row.titleName {
                    ShortenedNameText(
                        row.title,
                        name: name,
                        compactSuffix: row.titleCompactCount,
                        style: .titleSmall,
                        weight: weight
                    )
                } else {
                    OneLineName(row.title, style: .titleSmall, weight: weight)
                }
            }
            .foregroundStyle(Palette.text)
            .accessibilityIdentifier("chatList.rowName")
        }
    }

    /// In place of the preview: a message of mine never went out, so say so before the chat opens.
    private struct NotSentLine: View {
        var body: some View {
            HStack(spacing: Spacing.extraSmall) {
                Image(systemName: "exclamationmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: ControlSize.iconSmall, height: ControlSize.iconSmall)
                    .accessibilityHidden(true)
                Text(ChatListStrings.string("chat.list.notSent"))
                    .waiveraTextStyle(.bodySmall, weight: .semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(Palette.dangerText)
        }
    }

    /// One line, as the conversation's typing slot: the whole line while it fits; once it would
    /// be cut, the name gives way and "is typing…" stays whole beside it.
    private struct TypingPreviewLine: View {
        let full: String
        let parts: TypingParts?

        var body: some View {
            Group {
                if let parts {
                    ViewThatFits(in: .horizontal) {
                        Text(full)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        HStack(spacing: 0) {
                            Text(parts.names)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Text(parts.rest)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)
                        }
                    }
                } else {
                    Text(full)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .waiveraTextStyle(.bodySmall, weight: .bold)
            .italic()
            .foregroundStyle(Palette.accent)
        }
    }

    /// The preview: an attachment glyph, the bold sender prefix and two lines of text. Unread
    /// rows read in the primary ink; placeholders and system rows are italic.
    private struct PreviewLine: View {
        let row: ChatRow

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.extraSmall) {
                if row.hasAttachment {
                    Image(systemName: "paperclip")
                        .resizable()
                        .scaledToFit()
                        .frame(width: ControlSize.iconSmall, height: ControlSize.iconSmall)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }
                text
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(row.isUnread ? Palette.text : Palette.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }

        private var text: Text {
            let isMuted = row.previewKind == .placeholder || row.previewKind == .system
            let body = isMuted ? Text(row.preview).italic() : Text(row.preview)
            guard let sender = row.senderPrefix else { return body }
            let prefix = Text(ChatListStrings.format("chat.list.preview.senderPrefix", sender))
                .font(TextStyleToken.bodySmall.font(weight: .semibold))
            // Interpolation instead of `Text + Text`, which the iOS 26 SDK deprecates.
            return Text("\(prefix) \(body)")
        }
    }

    /// "Call in progress · Join" as a tonal pill with a 44pt target. Its own tap target, so a tap
    /// never opens the conversation. At large text, or whenever the full line would be cut, it
    /// says "Join call": the verb is why the pill exists. VoiceOver hears the full line.
    private struct CallJoinButton: View {
        let isOpening: Bool
        let action: () -> Void

        @Environment(\.dynamicTypeSize) private var typeSize

        var body: some View {
            Button(action: action) {
                Group {
                    if typeSize.isLargeText {
                        pill(ChatListStrings.string("chat.list.call.joinShort"))
                    } else {
                        ViewThatFits(in: .horizontal) {
                            pill(ChatListStrings.string("chat.list.call.join"))
                            pill(ChatListStrings.string("chat.list.call.joinShort"))
                        }
                    }
                }
                .frame(minHeight: ControlSize.minHitTarget)
                .contentShape(Rectangle())
            }
            // Its own style keeps this button apart from the row's tap inside a List.
            .buttonStyle(.pressScale)
            .disabled(isOpening)
            .accessibilityLabel(
                Text(ChatListStrings.string(isOpening ? "chat.list.call.opening" : "chat.list.call.join"))
            )
            .accessibilityIdentifier("chatList.joinCall")
        }

        private func pill(_ label: String) -> some View {
            HStack(spacing: Spacing.extraSmall + Spacing.xxSmall) {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: Spacing.small, height: Spacing.small)
                if isOpening {
                    BusyIndicator(color: Palette.onAccentSoft, size: ControlSize.iconSmall)
                } else {
                    Image(systemName: "video.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: ControlSize.iconSmall, height: ControlSize.iconSmall)
                        .accessibilityHidden(true)
                }
                Text(label)
                    .waiveraTextStyle(.bodySmall, weight: .bold)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(Palette.onAccentSoft)
            .padding(.horizontal, Spacing.mediumSmall)
            .padding(.vertical, Spacing.extraSmall)
            .background(Palette.accentSoft, in: Capsule())
        }
    }

    /// Channel, bot and group tiles, or the peer's avatar. Channels, groups and the bot are
    /// conversations, so they share the brand tile; an archived channel is inactive, so neutral.
    struct RowLeadingView: View {
        let leading: RowLeading
        let avatar: Image?

        var body: some View {
            Group {
                switch leading {
                case .channel(let archived):
                    IconTile(systemImage: archived ? "archivebox.fill" : "number", tone: archived ? .neutral : .brand)
                case .bot:
                    LogoTile()
                case .group:
                    IconTile(systemImage: "person.2.fill", tone: .brand)
                case .direct(_, let name):
                    AvatarView(name: name, image: avatar, size: ControlSize.iconTile)
                }
            }
            // The row's label already says what kind of chat it is.
            .accessibilityHidden(true)
        }
    }

    #if DEBUG
        private struct RowGallery: View {
            var body: some View {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(ChatListPreviewData.rows) { row in
                            ConversationRowView(row: row, avatar: nil, onJoinCall: {})
                        }
                    }
                    .background(Palette.surface, in: InboxCardPosition.single.shape)
                    .padding(Spacing.gutter)
                }
                .background(Palette.background)
            }
        }

        #Preview("Light") { RowGallery() }
        #Preview("Dark") { RowGallery().preferredColorScheme(.dark) }
        #Preview("AX5") { RowGallery().dynamicTypeSize(.accessibility5) }
    #endif
#endif
