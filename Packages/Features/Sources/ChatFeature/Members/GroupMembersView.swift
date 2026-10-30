#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// A group's members (spec §9.2, v7 item 4), pushed from the "N members" button in the
    /// conversation header. A full screen, not a sheet: a row opens the person's page and Message
    /// opens a chat, both pushed, and back from either lands on this list with its search intact.
    /// The router passes the conversation id as `channelID` and wires the two callbacks.
    public struct GroupMembersView: View {
        let channelID: Int
        let onOpenPerson: (_ userID: String) -> Void
        let onOpenConversation: (_ conversationID: Int) -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: GroupMembersModel?

        public init(
            channelID: Int,
            onOpenPerson: @escaping (_ userID: String) -> Void,
            onOpenConversation: @escaping (_ conversationID: Int) -> Void
        ) {
            self.channelID = channelID
            self.onOpenPerson = onOpenPerson
            self.onOpenConversation = onOpenConversation
        }

        public var body: some View {
            Group {
                if let model {
                    GroupMembersScreen(
                        model: model,
                        avatars: data?.avatars,
                        onOpenPerson: onOpenPerson,
                        onOpenConversation: onOpenConversation
                    )
                } else {
                    Palette.background.ignoresSafeArea()
                }
            }
            .task(id: channelID) {
                guard let data else { return }
                // Kept across a push and pop, so the search survives a visit to a person.
                let current = model?.channelID == channelID ? model : nil
                let active =
                    current ?? GroupMembersModel(channelID: channelID, source: GroupMembersSource(environment: data))
                model = active
                await active.run()
            }
        }
    }

    /// The members screen for a model: "Members" with the count under it, a search on a long
    /// list, and everyone on one card, me first. Loading settles in over row skeletons after
    /// ~300ms; a failed load and an empty list get the shared states. Silent throughout.
    struct GroupMembersScreen: View {
        @Bindable var model: GroupMembersModel
        var avatars: (any AvatarRepository)?
        var onOpenPerson: (_ userID: String) -> Void = { _ in }
        var onOpenConversation: (_ conversationID: Int) -> Void = { _ in }

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var state: GroupMembersState { model.state }

        var body: some View {
            VStack(spacing: 0) {
                // One connection signal: a failed load already explains itself.
                if let connection = state.connection, !isError {
                    BannerView(
                        connection == .offline ? .offline : .reconnecting,
                        message: connection == .offline
                            ? ConversationStrings.text("members.offline.saved")
                            : ConversationStrings.subtitle(connection),
                        actionTitle: ConversationStrings.text("retry"),
                        action: { Task { await model.retryConnection() } }
                    )
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, Spacing.extraSmall)
                }
                if state.showsSearch {
                    MembersSearchField(query: $model.query)
                }
                if let error = state.messageError {
                    BannerView(.error, message: error.userMessage, onDismiss: { model.dismissMessageError() })
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.vertical, Spacing.extraSmall)
                        .transition(Motion.transition(edge: .top, reduceMotion: reduceMotion))
                }
                LoadingContent(isLoading: state.content == .loading) {
                    content
                } skeleton: {
                    SkeletonList()
                        .padding(.horizontal, Spacing.gutter)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(ConversationStrings.text("members.loading"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Palette.background)
            .waiveraAnimation(.state, value: state.messageError)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ChatHeaderTitle(
                        title: ConversationStrings.text("members.title"),
                        subtitle: state.totalCount > 0 ? ConversationStrings.members(state.totalCount) : nil
                    )
                }
            }
        }

        private var isError: Bool {
            if case .error = state.content { return true }
            return false
        }

        @ViewBuilder private var content: some View {
            switch state.content {
            case .loading:
                EmptyView()
            case .error(let error):
                EmptyStateView.error(
                    title: ConversationStrings.text("members.error.title"),
                    message: error.userMessage,
                    onRetry: { Task { await model.retry() } }
                )
            case .empty:
                if state.isNoMatch {
                    EmptyStateView(
                        illustration: .search,
                        title: ConversationStrings.text("members.no.match.title"),
                        message: ConversationStrings.text("members.no.match.message"),
                        actionTitle: ConversationStrings.text("members.search.clear")
                    ) { model.query = "" }
                } else {
                    EmptyStateView(
                        illustration: .connections,
                        title: ConversationStrings.text("members.empty.title"),
                        message: ConversationStrings.text("members.empty.message")
                    )
                }
            case .members:
                ScrollView {
                    CardGroup {
                        ForEach(state.rows) { row in
                            MemberRowView(
                                row: row,
                                isOpening: state.openingChatWith == row.userId,
                                isBusy: state.openingChatWith != nil,
                                avatars: avatars,
                                onOpen: { onOpenPerson(row.userId) },
                                onMessage: { message(row.userId) }
                            )
                            if row.id != state.rows.last?.id {
                                Rectangle()
                                    .fill(Palette.border)
                                    .frame(height: Spacing.hairline)
                                    .padding(.leading, Spacing.gutter + ControlSize.avatarMedium + Spacing.mediumSmall)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, Spacing.small)
                    .waiveraAnimation(.layout, value: state.rows.map(\.id))
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }

        private func message(_ userId: String) {
            Task {
                if let id = await model.message(userId) { onOpenConversation(id) }
            }
        }
    }

    /// One member: a 44pt soft-square avatar, the name on one line, and Message at the end, or
    /// "You" on my own row (there is no chat with myself). The row opens the person's page.
    private struct MemberRowView: View {
        let row: MemberRow
        let isOpening: Bool
        let isBusy: Bool
        let avatars: (any AvatarRepository)?
        let onOpen: () -> Void
        let onMessage: () -> Void

        private var name: String {
            row.name.isEmpty ? ConversationStrings.text("members.unknown") : row.name
        }

        var body: some View {
            HStack(spacing: Spacing.small) {
                Button(action: onOpen) {
                    HStack(spacing: Spacing.mediumSmall) {
                        ChatAvatar(
                            userId: row.userId,
                            name: name,
                            size: ControlSize.avatarMedium,
                            loader: { id in await avatars?.avatar(userId: id) }
                        )
                        OneLineName(name, style: .titleSmall)
                            .foregroundStyle(Palette.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, Spacing.small)
                    .frame(minHeight: ControlSize.listRowMinHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.row))
                .accessibilityLabel(name)
                .accessibilityHint(ConversationStrings.text("members.open.person"))
                trailing
            }
            .padding(.leading, Spacing.gutter)
            .padding(.trailing, Spacing.small)
        }

        @ViewBuilder private var trailing: some View {
            if row.isMe {
                StatusBadge(ConversationStrings.text("members.you"), tone: .accent)
                    .padding(.trailing, Spacing.small)
            } else if isOpening {
                BusyIndicator()
                    .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                    .accessibilityElement()
                    .accessibilityLabel(ConversationStrings.format("members.opening", name))
            } else {
                Button(action: onMessage) {
                    Image(systemName: "bubble.left")
                        .resizable()
                        .scaledToFit()
                        .frame(width: ControlSize.smallIcon, height: ControlSize.smallIcon)
                        .foregroundStyle(Palette.accent)
                        .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press(.compact))
                .disabled(isBusy)
                .accessibilityLabel(ConversationStrings.format("members.message", name))
            }
        }
    }

    /// The search over a long list: shown only above ten members, it filters by name.
    private struct MembersSearchField: View {
        @Binding var query: String

        var body: some View {
            HStack(spacing: Spacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
                TextField(ConversationStrings.text("members.search.placeholder"), text: $query)
                    .waiveraTextStyle(.bodyMedium)
                    .foregroundStyle(Palette.text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityLabel(ConversationStrings.text("members.search.label"))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.compact))
                    .accessibilityLabel(ConversationStrings.text("members.search.clear"))
                }
            }
            .padding(.leading, Spacing.medium)
            .frame(minHeight: ControlSize.fieldHeight)
            .background(Palette.field, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .strokeBorder(Palette.fieldBorder, lineWidth: ControlSize.fieldBorder)
            )
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.small)
        }
    }

    #if DEBUG
        enum GroupMembersPreviewData {
            static let rows = [
                MemberRow(userId: "usr_alex", name: "Alex Rivera", isMe: true),
                MemberRow(userId: "usr_jordan", name: "Jordan Lee", isMe: false),
                MemberRow(
                    userId: "usr_mf",
                    name: "Maria-Fernanda Alejandra Castellanos-Whitaker de la Vega Rui",
                    isMe: false
                ),
                MemberRow(userId: "usr_priya", name: "Priya Raman", isMe: false),
                MemberRow(userId: "usr_w40", name: "Wolfeschlegelsteinhausenbergerdorffvoral", isMe: false),
            ]

            static let content = GroupMembersState(content: .members, rows: rows, totalCount: rows.count)
            static let long = GroupMembersState(
                content: .members,
                rows: rows + (1...7).map { MemberRow(userId: "usr_\($0)", name: "Care worker \($0)", isMe: false) },
                totalCount: rows.count + 7
            )
            static let error = GroupMembersState(content: .error(.offline), connection: .offline)
        }

        #Preview("Light") {
            NavigationStack { GroupMembersScreen(model: GroupMembersModel(preview: GroupMembersPreviewData.content)) }
        }

        #Preview("Dark, search") {
            NavigationStack { GroupMembersScreen(model: GroupMembersModel(preview: GroupMembersPreviewData.long)) }
                .preferredColorScheme(.dark)
        }

        #Preview("AX5") {
            NavigationStack { GroupMembersScreen(model: GroupMembersModel(preview: GroupMembersPreviewData.content)) }
                .dynamicTypeSize(.accessibility5)
        }

        #Preview("Error") {
            NavigationStack { GroupMembersScreen(model: GroupMembersModel(preview: GroupMembersPreviewData.error)) }
        }

        #Preview("Demo data") {
            NavigationStack {
                GroupMembersView(channelID: 7, onOpenPerson: { _ in }, onOpenConversation: { _ in })
            }
            .fakeDataEnvironment()
        }
    #endif
#endif
