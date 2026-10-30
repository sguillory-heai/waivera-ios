#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// What the overlay's controls do. Every one but Copy closes the overlay through the model.
    struct MessageFocusActions {
        var onDismiss: @MainActor () -> Void = {}
        var onReact: @MainActor (String) -> Void = { _ in }
        var onReply: @MainActor () -> Void = {}
        var onCopy: @MainActor () -> Void = {}
        var onCopiedShown: @MainActor () -> Void = {}
        var onEdit: @MainActor () -> Void = {}
        var onBookmark: @MainActor () -> Void = {}
        var onDelete: @MainActor () -> Void = {}
    }

    /// The long press on a message (spec §9.1, Android `MessageFocusOverlay`): the chat dims under
    /// the focus scrim, the pressed bubble lifts where it is, the six quick reactions float above
    /// it in one pill and a short menu sits under it, or beside it on a short window. A long
    /// message is clamped and scrolls inside the bubble, with fades. Nothing here vibrates.
    ///
    /// It is presented as a clear full-screen cover (see `ChatSheets`), so it covers the bar and
    /// the composer, is modal for VoiceOver and gets the real safe area, keyboard included.
    /// `anchor` is the pressed bubble's frame in the global space, from `FocusAnchors`.
    struct MessageFocusOverlay: View {
        let model: MessageActionsModel
        let anchor: CGRect?
        let actions: MessageFocusActions

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @State private var lifted = false
        @State private var appeared = false

        private var entrance: FocusEntrance { FocusEntrance(reduceMotion: reduceMotion) }

        var body: some View {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    scrim
                    pieces(in: proxy)
                }
            }
            .ignoresSafeArea()
            .accessibilityAction(.escape) { actions.onDismiss() }
            .onAppear(perform: enter)
            .task(id: model.copied) {
                guard model.copied else { return }
                try? await Task.sleep(for: .seconds(ChatMetrics.focusCopiedHold))
                guard !Task.isCancelled else { return }
                actions.onCopiedShown()
            }
        }

        /// The reader covers the whole window, so its insets are the bars, the cutout and the
        /// keyboard; nothing is placed outside them, less a gutter at the sides and a gap above
        /// and below.
        private func pieces(in proxy: GeometryProxy) -> some View {
            let insets = proxy.safeAreaInsets
            let origin = proxy.frame(in: .global).origin
            let safe = CGRect(
                x: insets.leading + Spacing.gutter,
                y: insets.top + ChatMetrics.focusGap,
                width: max(0, proxy.size.width - insets.leading - insets.trailing - Spacing.gutter * 2),
                height: max(0, proxy.size.height - insets.top - insets.bottom - ChatMetrics.focusGap * 2)
            )
            return FocusOverlayLayout(
                safe: safe,
                anchor: anchor.map { $0.offsetBy(dx: -origin.x, dy: -origin.y) },
                mine: model.isMine,
                menuTarget: dynamicTypeSize.isLargeText ? ChatMetrics.focusMenuWidthLarge : ChatMetrics.focusMenuWidth,
                progress: lifted ? 1 : 0,
                entrance: entrance
            ) {
                if model.canReact {
                    FocusReactionPill(onReact: actions.onReact)
                        .scaleEffect(piecesScale, anchor: model.isMine ? .bottomTrailing : .bottomLeading)
                        .opacity(appeared ? 1 : 0)
                        .accessibilitySortPriority(2)
                        .layoutValue(key: FocusPartKey.self, value: .pill)
                }
                LiftedBubble(model: model)
                    .scaleEffect(lifted ? 1 : entrance.bubbleFrom)
                    .opacity(entrance.bubbleFades && !appeared ? 0 : 1)
                    .accessibilitySortPriority(1)
                    .layoutValue(key: FocusPartKey.self, value: .bubble)
                FocusMenu(model: model, actions: actions)
                    .scaleEffect(piecesScale, anchor: model.isMine ? .topTrailing : .topLeading)
                    .opacity(appeared ? 1 : 0)
                    .accessibilitySortPriority(3)
                    .layoutValue(key: FocusPartKey.self, value: .menu)
            }
        }

        private var piecesScale: CGFloat { lifted ? 1 : entrance.piecesFrom }

        /// The 0.70 (0.76 in dark) scrim; a tap anywhere outside the pieces closes.
        private var scrim: some View {
            Palette.focusScrim
                .opacity(appeared ? 1 : 0)
                .contentShape(Rectangle())
                .onTapGesture { actions.onDismiss() }
                .accessibilityElement()
                .accessibilityLabel(ConversationStrings.text("action.close"))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { actions.onDismiss() }
                .accessibilitySortPriority(0)
        }

        /// With motion: the bubble lifts from its long-press sink on the pop spring while the pill
        /// and menu grow out of its edges and fade in. Reduce Motion only fades (150ms).
        private func enter() {
            withAnimation(Motion.animation(entrance.fade)) { appeared = true }
            if let lift = entrance.lift {
                withAnimation(Motion.animation(lift)) { lifted = true }
            } else {
                lifted = true
            }
        }
    }

    #if DEBUG
        private struct FocusOverlayPreview: View {
            var isMine = true
            var text = "Can someone cover the 3pm handoff at Maple House? I'm stuck at the clinic."

            var body: some View {
                var message = ChatMessage(id: 1, conversationId: 7, createdAt: Date())
                message.content = text
                let model = MessageActionsModel(
                    message: message,
                    rich: nil,
                    canReact: true,
                    canReply: true,
                    canEdit: isMine,
                    canDelete: isMine,
                    canCopy: true,
                    isMine: isMine
                )
                return ZStack {
                    Palette.background.ignoresSafeArea()
                    MessageFocusOverlay(model: model, anchor: nil, actions: MessageFocusActions())
                }
            }
        }

        #Preview("Light") { FocusOverlayPreview() }
        #Preview("Dark") { FocusOverlayPreview(isMine: false).preferredColorScheme(.dark) }
        #Preview("AX5, long") {
            FocusOverlayPreview(text: String(repeating: "A long message that keeps going. ", count: 80))
                .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
