#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// The button alternative to every swipe action, opened by a long press on a row. It opens with
    /// the conversation's own tile and one-line name, as the row shows them, so the sheet says
    /// which chat its actions touch (Android `RowActionsContent`, UI3-17). No haptic.
    struct RowActionsSheet: View {
        let row: ChatRow
        let avatar: Image?
        let onOpen: () -> Void
        let onMarkRead: () -> Void
        let onJoinCall: () -> Void
        let onViewProfile: (String) -> Void

        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: Spacing.mediumSmall) {
                        RowLeadingView(leading: row.leading, avatar: avatar)
                        ChatRowTitle(row: row)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, Spacing.mediumSmall)
                    .frame(minHeight: ControlSize.listRowMinHeight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(row.title))
                    .accessibilityAddTraits(.isHeader)
                    Rectangle()
                        .fill(Palette.border)
                        .frame(height: Spacing.hairline)
                    action("chat.list.action.open", systemImage: "bubble.left.fill", perform: onOpen)
                    if row.isUnread {
                        action("chat.list.action.markRead", systemImage: "envelope.open.fill", perform: onMarkRead)
                    }
                    if row.isCallLive {
                        action("chat.list.call.joinAction", systemImage: "video.fill", perform: onJoinCall)
                    }
                    if let userId = row.profileUserId {
                        action("chat.list.action.profile", systemImage: "person.fill") { onViewProfile(userId) }
                    }
                }
                .padding(.vertical, Spacing.small)
            }
            .background(Palette.surface)
        }

        private func action(_ key: String, systemImage: String, perform: @escaping () -> Void) -> some View {
            Button(action: perform) {
                ListRow(title: ChatListStrings.string(key)) {
                    IconTile(systemImage: systemImage)
                }
                .background(Palette.surface)
            }
            .buttonStyle(.press(.row))
            .accessibilityIdentifier("chatList.actions.\(key)")
        }
    }

    #if DEBUG
        private struct SheetPreview: View {
            var body: some View {
                RowActionsSheet(
                    row: ChatListPreviewData.rows[0],
                    avatar: nil,
                    onOpen: {},
                    onMarkRead: {},
                    onJoinCall: {},
                    onViewProfile: { _ in }
                )
            }
        }

        #Preview("Light") { SheetPreview() }
        #Preview("Dark") { SheetPreview().preferredColorScheme(.dark) }
        #Preview("AX5") { SheetPreview().dynamicTypeSize(.accessibility5) }
    #endif
#endif
