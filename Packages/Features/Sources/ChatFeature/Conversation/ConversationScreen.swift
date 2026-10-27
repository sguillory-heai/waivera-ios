#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The conversation screen for a model: header, timeline, typing, composer and sheets.
    struct ConversationScreen: View {
        @Bindable var model: ConversationModel
        var avatars: (any AvatarRepository)?
        var onOpenPerson: (_ userID: String) -> Void = { _ in }

        private var state: ConversationState { model.state }

        var body: some View {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if state.call.isLive {
                        CallBanner(isOpening: state.call.isOpening) { Task { await model.openCall() } }
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
                    subtitle: state.subtitle.map(ConversationStrings.subtitle)
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
            actions.longPress = { model.openActions($0) }
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
                onEdit: { model.startEdit($0) }
            )
        }
    }

    /// The header title with the connection state under it (03 §1).
    struct ChatHeaderTitle: View {
        let title: String
        let subtitle: String?

        var body: some View {
            VStack(spacing: 0) {
                Text(title)
                    .font(WaiveraFont.bodyEmphasis)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
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
