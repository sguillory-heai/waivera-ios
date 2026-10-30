#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// A section that failed while the rest of Today works: a quiet row (a neutral tile, the
    /// message, a text Retry), not a danger banner, so it is never louder than a failed send.
    struct SectionErrorView: View {
        let message: String
        let onRetry: () -> Void

        var body: some View {
            HStack(spacing: Spacing.mediumSmall) {
                IconTile(
                    systemImage: "exclamationmark.circle",
                    tone: .neutral,
                    size: ControlSize.iconTileSmall,
                    glyphSize: ControlSize.iconTileSmallGlyph
                )
                Text(message)
                    .waiveraTextStyle(.bodyMedium)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                WaiveraButton(TodayStrings.text("today.retry"), variant: .text, action: onRetry)
            }
            .padding(.leading, Spacing.gutter)
            .padding(.trailing, Spacing.small)
            .frame(minHeight: ControlSize.listRowMinHeight)
            .accessibilityElement(children: .combine)
        }
    }

    /// A quiet line of secondary text: empty sections, the stale timestamp, offline.
    struct QuietLine: View {
        let text: String
        var systemImage: String?

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }
                Text(text)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .waiveraTextStyle(.bodySmall)
            .padding(.horizontal, Spacing.gutter)
            .frame(minHeight: ControlSize.minHitTarget)
            .accessibilityElement(children: .combine)
        }
    }

    /// First-load skeleton on the sheet, shaped like the final screen: a section header and three
    /// cards, twice. The hero above shows its own placeholder card.
    struct TodaySkeleton: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<TodaySkeletonShape.sections, id: \.self) { section in
                    SkeletonLine(style: .titleMedium, share: TodaySkeletonShape.header)
                        .frame(maxWidth: .infinity, minHeight: ControlSize.minHitTarget, alignment: .leading)
                        .padding(.leading, Spacing.gutter + Spacing.extraSmall)
                        .padding(.trailing, Spacing.gutter)
                        .padding(.top, section == 0 ? Spacing.mediumSmall : Spacing.large)
                        .padding(.bottom, Spacing.xxSmall)
                    SectionSkeleton(labelled: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(TodayStrings.text("today.loading")))
        }
    }

    /// Placeholder cards for one section whose source is still loading.
    struct SectionSkeleton: View {
        var labelled = true

        var body: some View {
            VStack(spacing: 0) {
                ForEach(0..<TodaySkeletonShape.rows, id: \.self) { _ in SkeletonCard() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(labelled ? TodayStrings.text("today.loading") : ""))
            .accessibilityHidden(!labelled)
        }
    }

    /// A skeleton Today card: the same lifted card, padding, tile and gap, with bones for the
    /// kicker, a two-line headline and the supporting line, each at its text style's height.
    private struct SkeletonCard: View {
        var body: some View {
            HStack(spacing: TodayCard.gap) {
                SkeletonBlock(
                    width: ControlSize.cardTile,
                    height: ControlSize.cardTile,
                    cornerRadius: AvatarGeometry.cornerRadius(size: ControlSize.cardTile)
                )
                VStack(alignment: .leading, spacing: 0) {
                    SkeletonLine(style: .kicker, share: TodaySkeletonShape.eyebrow)
                        .padding(.bottom, Spacing.xxSmall)
                    SkeletonLine(style: .titleSmall, share: TodaySkeletonShape.title)
                    SkeletonLine(style: .titleSmall, share: TodaySkeletonShape.titleEnd)
                    SkeletonLine(style: .bodySmall, share: TodaySkeletonShape.supporting)
                        .padding(.top, Spacing.xxSmall)
                }
            }
            .padding(TodayCard.padding)
            .frame(maxWidth: .infinity, minHeight: ControlSize.listRowMinHeight, alignment: .leading)
            .todayCard(radius: Radius.sheetCard)
            .todayCardSpacing()
        }
    }

    /// A bone in one line of `style` (so it keeps the loaded text's height at every Dynamic Type
    /// size), `share` of the line's width, at the skeleton line's thickness.
    private struct SkeletonLine: View {
        let style: TextStyleToken
        let share: CGFloat

        var body: some View {
            Text(verbatim: " ")
                .waiveraTextStyle(style)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hidden()
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        SkeletonBlock(width: proxy.size.width * share, height: ControlSize.skeletonLine)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .accessibilityHidden(true)
        }
    }

    private enum TodaySkeletonShape {
        static let sections = 2
        static let rows = 3
        static let header: CGFloat = 0.35
        static let eyebrow: CGFloat = 0.3
        static let title: CGFloat = 0.6
        static let titleEnd: CGFloat = 0.35
        static let supporting: CGFloat = 0.45
    }

    /// The snackbar for a Today toast (Android `WaiveraSnackbarHost`): the inverse pill with Undo
    /// for an answered invitation, Retry for a failure, or no action for a plain confirmation.
    struct TodayToastView: View {
        let toast: TodayToast
        let onAction: () -> Void

        var body: some View {
            SnackbarView(
                message: toast.notice.message,
                actionTitle: actionTitle,
                actionIdentifier: toast.notice.offersUndo ? "today.toast.undo" : "today.toast.retry",
                action: actionTitle == nil ? nil : onAction
            )
            .accessibilityIdentifier("today.toast")
        }

        private var actionTitle: String? {
            if toast.notice.offersUndo { return TodayStrings.text("today.undo") }
            return toast.notice.offersRetry ? TodayStrings.text("today.retry") : nil
        }
    }

    extension View {
        /// Shows the feedback's toast at the bottom, announces it, and closes it after the toast
        /// timeout (longer with VoiceOver). `onClose` hears a toast that went away without its
        /// action, so a held invitation answer can go out at once.
        func todayFeedback(
            _ feedback: TodayFeedback,
            onAction: @escaping (TodayToast) -> Void,
            onClose: ((TodayToast) -> Void)? = nil
        ) -> some View {
            modifier(TodayFeedbackModifier(feedback: feedback, onAction: onAction, onClose: onClose))
        }
    }

    private struct TodayFeedbackModifier: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
        let feedback: TodayFeedback
        let onAction: (TodayToast) -> Void
        let onClose: ((TodayToast) -> Void)?

        func body(content: Content) -> some View {
            content
                .overlay(alignment: .bottom) {
                    if let toast = feedback.toast {
                        TodayToastView(toast: toast, onAction: { onAction(toast) })
                            .padding(Spacing.medium)
                            .transition(Motion.transition(edge: .bottom, reduceMotion: reduceMotion))
                            .task(id: toast.id) {
                                AccessibilityNotification.Announcement(toast.notice.message).post()
                                let lifetime = voiceOver ? FeedbackTiming.undoToastAccessible : FeedbackTiming.undoToast
                                try? await Task.sleep(for: .seconds(lifetime))
                                guard !Task.isCancelled, feedback.toast?.id == toast.id else { return }
                                if let onClose { onClose(toast) } else { feedback.dismiss(toast.id) }
                            }
                    }
                }
                .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: feedback.toast)
        }
    }
#endif
