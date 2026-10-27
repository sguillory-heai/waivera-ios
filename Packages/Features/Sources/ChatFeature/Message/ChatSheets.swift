#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    /// What the shared sheets need from the screen that owns them.
    struct ChatSheetContext {
        var message: @MainActor (_ messageId: Int) -> ChatMessage?
        var summaries: @MainActor (_ messageId: Int) -> [ReactionSummary]
        var viewerId: String?
        var names: [String: String]
        var onReply: @MainActor (ChatMessage) -> Void
        var onEdit: @MainActor (ChatMessage) -> Void
    }

    extension View {
        /// The action, reaction, file, image and delete sheets plus the toast, shared by the
        /// conversation and the thread.
        func chatSheets(_ interactions: MessageInteractions, context: ChatSheetContext) -> some View {
            modifier(ChatSheetsModifier(interactions: interactions, context: context))
        }
    }

    private struct ChatSheetsModifier: ViewModifier {
        let interactions: MessageInteractions
        let context: ChatSheetContext

        func body(content: Content) -> some View {
            content
                .sheet(item: sheetBinding) { sheet in
                    sheetContent(sheet)
                        .presentationDragIndicator(.visible)
                        .presentationCornerRadius(Radius.sheet)
                        .presentationBackground(Palette.surface)
                }
                .fullScreenCover(item: imageBinding) { messageId in
                    ImagePreviewView(
                        messageId: messageId.value,
                        title: context.message(messageId.value)?.attachment?.name
                            ?? ConversationStrings.text("image.title"),
                        load: { try await interactions.download(messageId: $0) },
                        onClose: { interactions.dismissSheet() }
                    )
                }
                .overlay(alignment: .bottom) {
                    if let toast = interactions.toast {
                        ChatToastView(toast: toast, interactions: interactions)
                            .padding(.horizontal, Spacing.medium)
                            .padding(.bottom, Spacing.small)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .waiveraAnimation(.state, value: interactions.toast)
        }

        private var sheetBinding: Binding<ChatSheet?> {
            Binding(
                get: {
                    if case .imagePreview = interactions.sheet { return nil }
                    return interactions.sheet
                },
                set: { if $0 == nil { interactions.dismissSheet() } }
            )
        }

        private var imageBinding: Binding<MessageID?> {
            Binding(
                get: {
                    guard case .imagePreview(let messageId) = interactions.sheet else { return nil }
                    return MessageID(value: messageId)
                },
                set: { if $0 == nil { interactions.dismissSheet() } }
            )
        }

        @ViewBuilder
        private func sheetContent(_ sheet: ChatSheet) -> some View {
            switch sheet {
            case .actions(let model):
                actionSheet(model).presentationDetents([.medium, .large])
            case .reactions(let messageId, let emoji):
                ReactionDetailsSheet(
                    reactions: context.message(messageId)?.reactions ?? [],
                    summaries: context.summaries(messageId),
                    initialEmoji: emoji,
                    viewerId: context.viewerId,
                    names: context.names,
                    onClose: { interactions.dismissSheet() }
                )
                .presentationDetents([.medium, .large])
            case .fileActions(let messageId, let fileName, let isBusy):
                FileActionsSheet(
                    fileName: fileName,
                    isBusy: isBusy,
                    preparedFile: interactions.preparedFile,
                    onSave: { prepare(messageId, .save) },
                    onShare: { prepare(messageId, .share) },
                    onFinish: { interactions.finishPreparedFile(completed: $0) }
                )
                .presentationDetents([.medium])
            case .confirmDelete(let messageId):
                ConfirmationSheet(
                    title: ConversationStrings.text("delete.title"),
                    message: ConversationStrings.text("delete.message"),
                    confirmTitle: ConversationStrings.text("delete.confirm"),
                    onConfirm: { Task { await interactions.confirmDelete(messageId: messageId) } }
                )
                .presentationDetents([.medium])
            case .imagePreview:
                EmptyView()
            }
        }

        private func actionSheet(_ model: MessageActionsModel) -> some View {
            let message = model.message
            return MessageActionSheet(
                model: model,
                onReact: { emoji in Task { await interactions.react(messageId: message.id, emoji: emoji) } },
                onCopy: { interactions.copy(message) },
                onReply: { context.onReply(message) },
                onEdit: { context.onEdit(message) },
                onBookmark: { Task { await interactions.toggleBookmark(messageId: message.id) } },
                onDelete: { interactions.requestDelete(messageId: message.id) },
                onClose: { interactions.dismissSheet() }
            )
        }

        private func prepare(_ messageId: Int, _ purpose: PreparedFile.Purpose) {
            guard let message = context.message(messageId) else { return }
            Task { await interactions.prepareFile(message, purpose: purpose) }
        }
    }

    /// `Int` is not `Identifiable`; the image cover needs an item.
    private struct MessageID: Identifiable, Hashable {
        let value: Int
        var id: Int { value }
    }

    /// Bookmark changes with Undo, and failures with their client-owned reason. Dismisses itself.
    private struct ChatToastView: View {
        let toast: ChatToast
        let interactions: MessageInteractions

        var body: some View {
            Group {
                switch toast.kind {
                case .bookmarkSaved(let messageId), .bookmarkRemoved(let messageId):
                    UndoToast(message: ConversationStrings.toast(toast.kind)) {
                        interactions.dismissToast()
                        Task { await interactions.undoBookmark(messageId: messageId) }
                    }
                case .fileSaved:
                    BannerView(
                        .info,
                        message: ConversationStrings.toast(toast.kind),
                        onDismiss: { interactions.dismissToast() }
                    )
                case .failed:
                    BannerView(
                        .error,
                        message: ConversationStrings.toast(toast.kind),
                        onDismiss: { interactions.dismissToast() }
                    )
                }
            }
            .task(id: toast.id) {
                let seconds =
                    UIAccessibility.isVoiceOverRunning ? FeedbackTiming.undoToastAccessible : FeedbackTiming.undoToast
                try? await Task.sleep(for: .seconds(seconds))
                if interactions.toast?.id == toast.id { interactions.dismissToast() }
            }
        }
    }
#endif
