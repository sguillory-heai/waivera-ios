#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// One inbox row: leading tile or avatar with an unread dot, title (wraps to two lines, and
    /// the time moves under it at accessibility sizes), preview with sender prefix or the
    /// typing / call override, and the unread badge. VoiceOver reads the row as one element;
    /// its actions are offered by the list (swipe, context menu and accessibility actions).
    struct ConversationRowView: View {
        let row: ChatRow
        let avatar: Image?
        let onJoinCall: () -> Void

        @Environment(\.dynamicTypeSize) private var typeSize

        var body: some View {
            HStack(alignment: .top, spacing: Spacing.smallPlus) {
                RowLeadingView(leading: row.leading, avatar: avatar, isUnread: row.isUnread)
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    titleLine
                    HStack(alignment: .center, spacing: Spacing.small) {
                        previewArea
                            .frame(maxWidth: .infinity, alignment: .leading)
                        CountBadge(count: row.unreadCount)
                    }
                }
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            }
            .padding(.vertical, Spacing.smallPlus)
            .frame(minHeight: ControlSize.minHitTarget)
        }

        @ViewBuilder private var titleLine: some View {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    title
                    time
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.extraSmall) {
                    title
                        .frame(maxWidth: .infinity, alignment: .leading)
                    time
                }
            }
        }

        private var title: some View {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.extraSmall) {
                Text(row.title)
                    .font(WaiveraFont.body)
                    .fontWeight(row.isUnread ? .heavy : .semibold)
                    .foregroundStyle(Palette.text)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
                if row.isReadOnly {
                    Image(systemName: "lock.fill")
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }
            }
        }

        @ViewBuilder private var time: some View {
            if !row.timeLabel.isEmpty {
                Text(row.timeLabel)
                    .font(WaiveraFont.captionEmphasis)
                    .foregroundStyle(row.isUnread ? Palette.accent : Palette.textSecondary)
                    .lineLimit(1)
            }
        }

        @ViewBuilder private var previewArea: some View {
            if row.isCallLive {
                CallJoinButton(isOpening: row.isOpeningCall, action: onJoinCall)
            } else if let typing = row.typingLabel {
                Text(typing)
                    .font(WaiveraFont.caption)
                    .fontWeight(.bold)
                    .italic()
                    .foregroundStyle(Palette.accent)
                    .lineLimit(2)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.extraSmall) {
                    if row.hasAttachment {
                        Image(systemName: "paperclip")
                            .font(WaiveraFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .accessibilityHidden(true)
                    }
                    previewText
                        .font(WaiveraFont.caption)
                        .foregroundStyle(row.isUnread ? Palette.text : Palette.textSecondary)
                        .lineLimit(2)
                }
            }
        }

        private var previewText: Text {
            let isMuted = row.previewKind == .placeholder || row.previewKind == .system
            let body = isMuted ? Text(row.preview).italic() : Text(row.preview)
            guard let sender = row.senderPrefix else { return body }
            let prefix = Text(ChatListStrings.format("chat.list.preview.senderPrefix", sender)).fontWeight(.semibold)
            // Interpolation instead of `Text + Text`, which the iOS 26 SDK deprecates.
            return Text("\(prefix) \(body)")
        }
    }

    /// "Call in progress · Join". Its own tap target, so tapping it never opens the conversation.
    private struct CallJoinButton: View {
        let isOpening: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: Spacing.extraSmall) {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: Spacing.small, height: Spacing.small)
                    if isOpening {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Palette.accent)
                    } else {
                        Image(systemName: "video.fill")
                            .font(WaiveraFont.caption)
                    }
                    Text(ChatListStrings.string("chat.list.call.join"))
                        .font(WaiveraFont.caption)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(Palette.accent)
                .frame(minHeight: ControlSize.minHitTarget)
                .contentShape(Rectangle())
            }
            // Borderless keeps this button separate from the row's own tap inside a List.
            .buttonStyle(.borderless)
            .disabled(isOpening)
            .accessibilityLabel(
                Text(ChatListStrings.string(isOpening ? "chat.list.call.opening" : "chat.list.call.joinAction"))
            )
        }
    }

    /// Channel, bot and group tiles, or the peer's avatar, with the unread dot.
    struct RowLeadingView: View {
        let leading: RowLeading
        let avatar: Image?
        let isUnread: Bool

        var body: some View {
            tile
                .overlay(alignment: .topTrailing) {
                    if isUnread {
                        Circle()
                            .fill(Palette.unread)
                            .frame(width: ControlSize.unreadDot, height: ControlSize.unreadDot)
                            .overlay(
                                Circle().strokeBorder(Palette.background, lineWidth: ControlSize.milestoneRingWidth)
                            )
                            .offset(x: Spacing.extraSmall / 2, y: -Spacing.extraSmall / 2)
                            .accessibilityHidden(true)
                    }
                }
        }

        @ViewBuilder private var tile: some View {
            switch leading {
            case .channel(let archived):
                IconTile(systemImage: archived ? "archivebox.fill" : "number")
            case .bot:
                IconTile(systemImage: "bell.badge.fill")
            case .group:
                IconTile(systemImage: "person.2.fill", tone: .neutral)
            case .direct(_, let name):
                AvatarView(name: name, image: avatar, size: ControlSize.iconTile)
                    .accessibilityHidden(true)
            }
        }
    }

    #if DEBUG
        private struct RowGallery: View {
            var body: some View {
                List {
                    ForEach(ChatListPreviewData.rows) { row in
                        ConversationRowView(row: row, avatar: nil, onJoinCall: {})
                            .listRowBackground(row.isUnread ? Palette.accentWash : Palette.background)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Palette.background)
            }
        }

        #Preview("Light") { RowGallery() }
        #Preview("Dark") { RowGallery().preferredColorScheme(.dark) }
        #Preview("AX XXXL") { RowGallery().dynamicTypeSize(.accessibility5) }
    #endif
#endif
