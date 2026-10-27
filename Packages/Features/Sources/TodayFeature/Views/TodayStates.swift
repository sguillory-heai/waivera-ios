#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// "You're all caught up": the one place the celebrate motion token is used. It settles in
    /// with a soft spring once; under Reduce Motion it fades in.
    struct AllCaughtUpView: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var appeared = false

        var body: some View {
            EmptyStateView(
                systemImage: "checkmark.seal.fill",
                title: TodayStrings.text("today.caughtUp.title"),
                message: TodayStrings.text("today.caughtUp.message")
            )
            .scaleEffect(appeared || reduceMotion ? 1 : Self.startScale)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(Motion.animation(.celebrate, reduceMotion: reduceMotion)) { appeared = true }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today.allCaughtUp")
        }

        private static let startScale: CGFloat = 0.85
    }

    /// An inline section error with Retry; the rest of the screen keeps working.
    struct SectionErrorView: View {
        let message: String
        let onRetry: () -> Void

        var body: some View {
            BannerView(.error, message: message, actionTitle: TodayStrings.text("today.retry"), action: onRetry)
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.extraSmall)
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
            .font(WaiveraFont.caption)
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .frame(minHeight: ControlSize.minHitTarget)
            .accessibilityElement(children: .combine)
        }
    }

    /// First-load skeleton shaped like the final list: section titles with rows.
    struct TodaySkeleton: View {
        var sections = 2

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<sections, id: \.self) { _ in
                    SkeletonBlock(width: ControlSize.avatarLarge)
                        .padding(.horizontal, Spacing.medium)
                        .padding(.top, Spacing.large)
                    SkeletonList(rows: 3)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(TodayStrings.text("today.loading")))
        }
    }

    /// A floating confirmation or error pill with an optional Retry, in place of a system alert.
    struct TodayToastView: View {
        let toast: TodayToast
        let onRetry: () -> Void
        let onDismiss: () -> Void

        var body: some View {
            HStack(spacing: Spacing.small) {
                Text(toast.notice.message)
                    .font(WaiveraFont.body)
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if toast.notice.offersRetry {
                    Button(TodayStrings.text("today.retry"), action: onRetry)
                        .font(WaiveraFont.button)
                        .foregroundStyle(Palette.accent)
                        .frame(minWidth: ControlSize.minHitTarget, minHeight: ControlSize.minHitTarget)
                        .accessibilityIdentifier("today.toast.retry")
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(WaiveraFont.captionEmphasis)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(TodayStrings.text("today.dismiss")))
            }
            .padding(.leading, Spacing.medium)
            .padding(.trailing, Spacing.extraSmall)
            .padding(.vertical, Spacing.extraSmall)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today.toast")
        }
    }

    extension View {
        /// Shows the feedback's toast at the bottom, announces it, clears it after the toast
        /// timeout (longer with VoiceOver), and plays the success and failure haptics.
        func todayFeedback(_ feedback: TodayFeedback, onRetry: @escaping (TodayToast) -> Void) -> some View {
            modifier(TodayFeedbackModifier(feedback: feedback, onRetry: onRetry))
        }
    }

    private struct TodayFeedbackModifier: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
        let feedback: TodayFeedback
        let onRetry: (TodayToast) -> Void

        func body(content: Content) -> some View {
            content
                .overlay(alignment: .bottom) {
                    if let toast = feedback.toast {
                        TodayToastView(
                            toast: toast,
                            onRetry: { onRetry(toast) },
                            onDismiss: { feedback.dismiss(toast.id) }
                        )
                        .padding(Spacing.medium)
                        .transition(Motion.transition(edge: .bottom, reduceMotion: reduceMotion))
                        .task(id: toast.id) {
                            AccessibilityNotification.Announcement(toast.notice.message).post()
                            let lifetime = voiceOver ? FeedbackTiming.undoToastAccessible : FeedbackTiming.undoToast
                            try? await Task.sleep(for: .seconds(lifetime))
                            if !Task.isCancelled { feedback.dismiss(toast.id) }
                        }
                    }
                }
                .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: feedback.toast)
                .waiveraHaptic(.success, trigger: feedback.successCount)
                .waiveraHaptic(.failure, trigger: feedback.failureCount)
        }
    }
#endif
