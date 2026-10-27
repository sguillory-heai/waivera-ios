#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The thread screen for a model: the root message, its replies and a text-only reply box.
    struct ThreadScreen: View {
        @Bindable var model: ThreadModel
        var avatars: (any AvatarRepository)?
        var onOpenPerson: (_ userID: String) -> Void = { _ in }

        private var state: ThreadState { model.state }

        var body: some View {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        ChatHeaderTitle(
                            title: ConversationStrings.text("thread.screen.title"),
                            subtitle: state.subtitle.map(ConversationStrings.subtitle)
                                ?? state.conversationTitle.map(ConversationStrings.title)
                        )
                    }
                }
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
                EmptyStateView(systemImage: "exclamationmark.bubble", title: ConversationStrings.text("thread.invalid"))
            case .loading:
                LoadingContent(isLoading: true) {
                    EmptyView()
                } skeleton: {
                    MessagesSkeleton()
                }
            case .error(let error):
                EmptyStateView.error(
                    title: ConversationStrings.text("thread.error.title"),
                    message: error.userMessage,
                    onRetry: { Task { await model.retryLoad() } }
                )
            case .ready:
                TimelineView(.periodic(from: .now, by: ChatMetrics.timeTick)) { tick in
                    TimelineList(
                        items: state.replies,
                        context: rowContext(now: tick.date),
                        actions: rowActions,
                        hasOlder: false,
                        isLoadingOlder: false,
                        scrollCommand: state.scrollCommand,
                        accessibilityLabelKey: "thread.list"
                    ) {
                        rootHeader(now: tick.date)
                    }
                }
            }
        }

        @ViewBuilder
        private func rootHeader(now: Date) -> some View {
            VStack(spacing: 0) {
                if state.isStale {
                    BannerView(.info, message: ConversationStrings.text("messages.stale"))
                        .padding(.horizontal, Spacing.medium)
                        .padding(.vertical, Spacing.small)
                }
                if let root = state.root {
                    MessageRowView(row: root, context: rowContext(now: now), actions: rowActions)
                } else {
                    Text(ConversationStrings.text("thread.root.missing"))
                        .font(WaiveraFont.body.italic())
                        .foregroundStyle(Palette.textSecondary)
                        .padding(Spacing.medium)
                }
                HStack(spacing: Spacing.smallPlus) {
                    Text(ConversationStrings.replyCountHeader(state.replyCount))
                        .font(WaiveraFont.captionEmphasis)
                        .foregroundStyle(Palette.textSecondary)
                    Rectangle().fill(Palette.border).frame(height: Spacing.hairline).accessibilityHidden(true)
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.smallPlus)
                .accessibilityAddTraits(.isHeader)
                if state.replies.isEmpty {
                    Text(ConversationStrings.text("thread.empty"))
                        .font(WaiveraFont.body)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.large)
                }
            }
            .id(state.root?.key ?? "thread-root")
        }

        @ViewBuilder private var bottomBar: some View {
            if model.isValid {
                VStack(spacing: Spacing.extraSmall) {
                    if let error = state.sendError {
                        SendErrorBanner(kind: error, noun: .reply) { model.dismissSendError() }
                    }
                    if let reason = state.readOnlyReason, state.canWrite == false {
                        ReadOnlyNotice(reason: reason)
                    } else {
                        ComposerView(
                            draft: $model.draft,
                            config: ComposerConfig(
                                placeholderKey: "composer.reply.placeholder",
                                sendLabelKey: "send.reply",
                                allowsImages: false,
                                isEnabled: state.canWrite == true,
                                canSend: model.canSend,
                                isEditing: state.editingMessageID != nil,
                                focusRequest: state.focusRequest
                            ),
                            onDraftChanged: { model.draftChanged() },
                            onSend: { Task { await model.send() } },
                            onCancelEdit: { model.cancelEdit() }
                        )
                    }
                }
                .padding(.top, Spacing.extraSmall)
                .background(Palette.background)
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
                summaries: { id in
                    if let root = model.state.root, root.message.id == id { return root.reactions }
                    return model.state.replies.lazy.compactMap { $0.reactionSummaries(id) }.first ?? []
                },
                viewerId: state.viewerId,
                names: state.names,
                onReply: { _ in model.replyFromSheet() },
                onEdit: { model.startEdit($0) }
            )
        }
    }
#endif
