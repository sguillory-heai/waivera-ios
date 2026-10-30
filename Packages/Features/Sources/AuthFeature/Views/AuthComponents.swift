#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Scrolling page for every auth screen. The scroll view is the single keyboard owner
    /// (11-pitfalls #31): it moves the focused field above the keyboard and dismisses it on drag.
    struct AuthScaffold<Content: View>: View {
        @ViewBuilder let content: Content

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    content
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.extraLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.background)
        }
    }

    /// Icon tile, screen title and a short explanation.
    struct AuthHeader: View {
        let systemImage: String
        let title: String
        let message: String
        var tone: TileTone = .brand

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.smallPlus) {
                IconTile(systemImage: systemImage, tone: tone)
                Text(title)
                    .font(WaiveraFont.screenTitle)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(WaiveraFont.body)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A surface card that groups a form.
    struct AuthCard<Content: View>: View {
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                content
            }
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: shape)
            .overlay(shape.strokeBorder(Palette.border, lineWidth: Spacing.hairline))
        }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        }
    }

    /// A caption under a busy button, announced to VoiceOver when it appears.
    struct AuthProgressCaption: View {
        let text: String

        var body: some View {
            Text(text)
                .font(WaiveraFont.caption)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .onAppear { AccessibilityNotification.Announcement(text).post() }
        }
    }

    extension View {
        /// Rejected credentials: the one auth outcome that vibrates (the form also shakes once,
        /// `rejectShake`). Every other failure and every success is silent; its message is enough.
        func signInRejectedFeedback(rejections: Int) -> some View {
            waiveraHaptic(.signInRejected, trigger: rejections) { old, new in new > old }
        }

        /// Fades and slides a notice in and out with the state motion token.
        func authNoticeTransition() -> some View {
            modifier(NoticeTransition())
        }
    }

    private struct NoticeTransition: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func body(content: Content) -> some View {
            content.transition(Motion.transition(edge: .top, reduceMotion: reduceMotion))
        }
    }
#endif

#if canImport(UIKit) && DEBUG
    import SwiftUI

    /// Renders `content` once an async fixture is ready, so previews show the same prepared
    /// states as the snapshot tests.
    struct FixturePreview<Model, Content: View>: View {
        private let make: @MainActor () async -> Model
        private let content: (Model) -> Content
        @State private var model: Model?

        init(
            _ make: @escaping @MainActor () async -> Model,
            @ViewBuilder content: @escaping (Model) -> Content
        ) {
            self.make = make
            self.content = content
        }

        var body: some View {
            Group {
                if let model {
                    content(model)
                } else {
                    Color.clear
                }
            }
            .task { model = await make() }
        }
    }
#endif
