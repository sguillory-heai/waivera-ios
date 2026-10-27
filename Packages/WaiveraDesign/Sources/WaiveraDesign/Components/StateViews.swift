#if canImport(UIKit)
    import SwiftUI

    /// The shared empty / error block: icon tile, title, message and an optional action.
    public struct EmptyStateView: View {
        private let systemImage: String
        private let title: String
        private let message: String?
        private let actionTitle: String?
        private let action: (() -> Void)?
        private let tint: Color

        public init(
            systemImage: String,
            title: String,
            message: String? = nil,
            actionTitle: String? = nil,
            action: (() -> Void)? = nil
        ) {
            self.init(
                systemImage: systemImage,
                title: title,
                message: message,
                actionTitle: actionTitle,
                action: action,
                tint: Palette.accent
            )
        }

        private init(
            systemImage: String,
            title: String,
            message: String?,
            actionTitle: String?,
            action: (() -> Void)?,
            tint: Color
        ) {
            self.systemImage = systemImage
            self.title = title
            self.message = message
            self.actionTitle = actionTitle
            self.action = action
            self.tint = tint
        }

        /// Error variant: a typed `WaiveraError` message (never raw server text) with Retry.
        public static func error(title: String, message: String, onRetry: (() -> Void)?) -> EmptyStateView {
            EmptyStateView(
                systemImage: "exclamationmark.triangle.fill",
                title: title,
                message: message,
                actionTitle: onRetry == nil ? nil : DesignStrings.retry,
                action: onRetry,
                tint: Palette.danger
            )
        }

        public var body: some View {
            VStack(spacing: Spacing.smallPlus) {
                IconTile(systemImage: systemImage, tint: tint)
                Text(title)
                    .font(WaiveraFont.sectionTitle)
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .font(WaiveraFont.body)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                if let actionTitle, let action {
                    WaiveraButton(actionTitle, variant: .secondary, action: action)
                        .padding(.top, Spacing.small)
                        .accessibilityIdentifier("state.action")
                }
            }
            .padding(Spacing.large)
            .frame(maxWidth: .infinity)
        }
    }

    /// Inline loading block with a caption. Only for first loads with no cached content; lists
    /// use `SkeletonList` and never cover content with a spinner.
    public struct LoadingStateView: View {
        private let caption: String

        public init(caption: String) {
            self.caption = caption
        }

        public var body: some View {
            VStack(spacing: Spacing.smallPlus) {
                ProgressView()
                    .tint(Palette.accent)
                Text(caption)
                    .font(WaiveraFont.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(Spacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private struct StateGallery: View {
        var body: some View {
            ScrollView {
                VStack(spacing: Spacing.medium) {
                    EmptyStateView(
                        systemImage: "checkmark.circle.fill",
                        title: "All caught up",
                        message: "New mentions and replies will show here.",
                        actionTitle: "Open chats",
                        action: {}
                    )
                    EmptyStateView.error(
                        title: "Couldn't load your schedule",
                        message: "Check your connection and try again.",
                        onRetry: {}
                    )
                    LoadingStateView(caption: "Loading Waivera…")
                }
            }
            .background(Palette.background)
        }
    }

    #Preview("Light") { StateGallery() }
    #Preview("Dark") { StateGallery().preferredColorScheme(.dark) }
    #Preview("AX XXXL") { StateGallery().dynamicTypeSize(.accessibility5) }
#endif
