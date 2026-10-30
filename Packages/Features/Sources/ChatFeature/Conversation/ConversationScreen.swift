#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The conversation screen for a model: header, timeline, typing, composer and sheets.
    struct ConversationScreen: View {
        @Bindable var model: ConversationModel
        var avatars: (any AvatarRepository)?
        var onOpenPerson: (_ userID: String) -> Void = { _ in }
        var onOpenMembers: ((_ conversationID: Int) -> Void)?

        @State private var anchors = FocusAnchors()

        private var state: ConversationState { model.state }

        var body: some View {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        if state.memberCount != nil, let subtitle = state.subtitle {
                            ConnectionStrip(subtitle: subtitle)
                        }
                        if state.call.isLive {
                            CallBanner(isOpening: state.call.isOpening) { Task { await model.openCall() } }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .chatSheets(model.interactions, context: sheetContext)
                .environment(
                    \.openURL,
                    OpenURLAction { url in
                        MainActor.assumeIsolated { model.interactions.openLink(url) }
                        return .handled
                    }
                )
        }

        @ViewBuilder private var content: some View {
            switch state.content {
            case .invalid:
                EmptyStateView(
                    systemImage: "exclamationmark.bubble",
                    title: ConversationStrings.text("conversation.invalid")
                )
            case .loading:
                LoadingContent(isLoading: true) {
                    EmptyView()
                } skeleton: {
                    MessagesSkeleton()
                }
            case .error(let error):
                EmptyStateView.error(
                    title: ConversationStrings.text("messages.error.title"),
                    message: error.userMessage,
                    onRetry: { Task { await model.retryLoad() } }
                )
            case .empty:
                EmptyStateView(
                    systemImage: "bubble.left.and.bubble.right",
                    title: ConversationStrings.text("messages.empty.title"),
                    message: ConversationStrings.text("messages.empty")
                )
            case .messages:
                TimelineView(.periodic(from: .now, by: ChatMetrics.timeTick)) { _ in
                    TimelineList(
                        items: state.items,
                        context: rowContext(now: model.clock.now),
                        actions: rowActions,
                        hasOlder: state.hasOlder && !state.olderFailed,
                        isLoadingOlder: state.isLoadingOlder,
                        scrollCommand: state.scrollCommand,
                        accessibilityLabelKey: "messages.list",
                        onLoadOlder: { Task { await model.loadOlder() } }
                    ) {
                        if state.olderFailed {
                            BannerView(
                                .error,
                                message: ConversationStrings.text("older.failed"),
                                actionTitle: ConversationStrings.text("retry"),
                                action: { Task { await model.loadOlder() } }
                            )
                            .padding(.horizontal, Spacing.medium)
                            .padding(.vertical, Spacing.small)
                        }
                        if state.isStale {
                            BannerView(.info, message: ConversationStrings.text("messages.stale"))
                                .padding(.horizontal, Spacing.medium)
                                .padding(.vertical, Spacing.small)
                        }
                    }
                }
            }
        }

        @ViewBuilder private var bottomBar: some View {
            if model.isValid {
                VStack(spacing: Spacing.extraSmall) {
                    TypingIndicator(label: state.typing)
                    if let error = state.sendError {
                        SendErrorBanner(kind: error, noun: .message) { model.dismissSendError() }
                    }
                    if let reason = state.readOnlyReason, state.canWrite == false {
                        ReadOnlyNotice(reason: reason)
                    } else {
                        ComposerView(
                            draft: $model.draft,
                            config: composerConfig,
                            onDraftChanged: { model.draftChanged() },
                            onSend: { Task { await model.send() } },
                            onCancelEdit: { model.cancelEdit() },
                            onStageImage: { model.stageImage($0) },
                            onRemoveImage: { model.removeStagedImage() },
                            onImageUnreadable: { model.interactions.fail(.imageUnreadable, nil) }
                        )
                    }
                }
                .background(Palette.background)
            }
        }

        private var composerConfig: ComposerConfig {
            ComposerConfig(
                isEnabled: state.canWrite == true,
                canSend: model.canSend,
                isUploading: state.isUploading,
                isEditing: state.editingMessageID != nil,
                stagedImage: state.stagedImage
            )
        }

        @ToolbarContentBuilder private var toolbar: some ToolbarContent {
            ToolbarItem(placement: .principal) {
                ChatHeaderTitle(
                    title: ConversationStrings.title(state.title),
                    groupName: groupName,
                    groupOthers: groupOthers,
                    subtitle: state.memberCount == nil ? state.subtitle.map(ConversationStrings.subtitle) : nil,
                    memberCount: state.memberCount,
                    onOpenMembers: onOpenMembers.map { open in { open(model.conversationID) } }
                )
            }
            ToolbarItem(placement: .topBarTrailing) {
                if state.call.isAvailable {
                    Button {
                        Task { await model.openCall() }
                    } label: {
                        Group {
                            if state.call.isOpening {
                                ProgressView()
                            } else {
                                Image(systemName: "video.fill").foregroundStyle(Palette.accent)
                            }
                        }
                        .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                        .background(Palette.accentSoft, in: Circle())
                    }
                    .disabled(state.call.isOpening || state.title == nil)
                    .accessibilityLabel(ConversationStrings.text(state.call.isLive ? "call.join" : "call.start"))
                }
            }
        }

        private var groupName: String? {
            guard case .group(let first, _) = state.title else { return nil }
            return ConversationStrings.groupFirstName(first)
        }

        private var groupOthers: Int {
            guard case .group(_, let others) = state.title else { return 0 }
            return others
        }

        private func rowContext(now: Date) -> RowContext {
            RowContext(
                now: now,
                zone: model.clock.timeZone,
                names: state.names,
                visibleTimestamps: state.visibleTimestamps,
                highlightKey: state.highlightKey
            )
        }

        private var rowActions: MessageRowActions {
            let model = model
            let interactions = model.interactions
            let avatars = avatars
            var actions = MessageRowActions()
            actions.toggleTimestamp = { model.toggleTimestamp($0) }
            let anchors = anchors
            actions.longPress = { model.openActions($0) }
            actions.recordAnchor = { anchors.record($0, bounds: $1) }
            if state.canWrite == true {
                actions.react = { id, emoji in Task { await interactions.react(messageId: id, emoji: emoji) } }
            }
            actions.reactionDetails = { interactions.openReactionDetails(messageId: $0, emoji: $1) }
            actions.openThread = { model.openThread($0) }
            actions.openAttachment = { interactions.openAttachment($0) }
            actions.openPerson = { onOpenPerson($0) }
            actions.retry = { id in Task { await model.retry(clientMessageId: id) } }
            actions.editFailed = { outgoing in Task { await model.editFailed(outgoing) } }
            actions.discard = { id in Task { await model.discard(clientMessageId: id) } }
            actions.openTicket = { interactions.openLink($0) }
            actions.loadImage = { try await interactions.download(messageId: $0) }
            actions.loadAvatar = { id in await avatars?.avatar(userId: id) }
            return actions
        }

        private var sheetContext: ChatSheetContext {
            let model = model
            return ChatSheetContext(
                message: { model.message($0) },
                summaries: { id in model.state.items.lazy.compactMap { $0.reactionSummaries(id) }.first ?? [] },
                viewerId: state.viewerId,
                names: state.names,
                onReply: { model.openThread($0) },
                onEdit: { model.startEdit($0) },
                anchor: { [anchors] in anchors.bounds(of: $0) }
            )
        }
    }

    /// The header title (spec §6.2, §9.2): the chat's name on one line that shrinks a little and
    /// then ends in "…", or a group's "Name & 4 others" where only the name is cut. Under it a
    /// group has its "N members" line, a button with a chevron to the members screen; other chats
    /// show the connection state there, when there is one.
    struct ChatHeaderTitle: View {
        let title: String
        var groupName: String?
        var groupOthers = 0
        var subtitle: String?
        var memberCount: Int?
        var onOpenMembers: (() -> Void)?

        var body: some View {
            if let memberCount, let onOpenMembers {
                Button(action: onOpenMembers) {
                    VStack(spacing: 0) {
                        titleLine
                        HStack(spacing: Spacing.xxSmall) {
                            Text(ConversationStrings.members(memberCount))
                                .waiveraTextStyle(.labelMedium)
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .resizable()
                                .scaledToFit()
                                .frame(width: ControlSize.iconSmall / 2, height: ControlSize.iconSmall / 2)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(minHeight: ControlSize.minHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.compact))
                .accessibilityElement(children: .combine)
                .accessibilityHint(ConversationStrings.text("members.show"))
                .accessibilityAddTraits(.isHeader)
            } else {
                VStack(spacing: 0) {
                    titleLine
                    if let line = subtitle ?? memberCount.map(ConversationStrings.members) {
                        OneLineName(line, style: .labelMedium)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
        }

        @ViewBuilder private var titleLine: some View {
            if let groupName {
                ShortenedNameText(groupTitle: title, firstName: groupName, others: groupOthers, style: .titleSmall)
                    .foregroundStyle(Palette.text)
            } else {
                OneLineName(title, style: .titleSmall)
                    .foregroundStyle(Palette.text)
            }
        }
    }

    /// The connection state for a group, whose header line is its members button.
    struct ConnectionStrip: View {
        let subtitle: ConnectionSubtitle

        var body: some View {
            BannerView(subtitle == .offline ? .offline : .reconnecting, message: ConversationStrings.subtitle(subtitle))
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.extraSmall)
        }
    }

    extension TimelineItem {
        /// The precomputed reaction summary of the message row with `messageId`.
        func reactionSummaries(_ messageId: Int) -> [ReactionSummary]? {
            guard case .message(let row) = self, row.message.id == messageId else { return nil }
            return row.reactions
        }
    }

    #if DEBUG
        #Preview("Messages, light") {
            NavigationStack {
                ConversationScreen(model: ChatPreviewData.conversationModel(.messages))
            }
        }

        #Preview("Messages, dark") {
            NavigationStack {
                ConversationScreen(model: ChatPreviewData.conversationModel(.messages))
            }
            .preferredColorScheme(.dark)
        }

        #Preview("Messages, AX5") {
            NavigationStack {
                ConversationScreen(model: ChatPreviewData.conversationModel(.messages))
            }
            .dynamicTypeSize(.accessibility5)
        }

        #Preview("Every state") {
            TabView {
                ForEach(ConversationPreviewVariant.allCases, id: \.self) { variant in
                    NavigationStack {
                        ConversationScreen(model: ChatPreviewData.conversationModel(variant))
                    }
                    .tabItem { Text(verbatim: variant.rawValue) }
                }
            }
        }
    #endif
#endif
