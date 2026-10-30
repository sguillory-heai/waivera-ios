#if canImport(UIKit)
    import SwiftUI

    /// The shared empty and error block (Android `WaiveraEmptyState`): a brand illustration (or an
    /// icon tile), title, message and an optional action, so every screen's empty, error and
    /// no-match states read the same. Illustrations are solid violet duotone on a lilac disc.
    public struct EmptyStateView: View {
        private enum Art {
            case icon(String, TileTone)
            case illustration(Illustration)
        }

        private let art: Art
        private let title: String
        private let message: String?
        private let actionTitle: String?
        private let action: (() -> Void)?
        private let dense: Bool

        public init(
            systemImage: String,
            title: String,
            message: String? = nil,
            actionTitle: String? = nil,
            dense: Bool = false,
            action: (() -> Void)? = nil
        ) {
            self.init(
                art: .icon(systemImage, .brand),
                title: title,
                message: message,
                actionTitle: actionTitle,
                dense: dense,
                action: action
            )
        }

        public init(
            illustration: Illustration,
            title: String,
            message: String? = nil,
            actionTitle: String? = nil,
            dense: Bool = false,
            action: (() -> Void)? = nil
        ) {
            self.init(
                art: .illustration(illustration),
                title: title,
                message: message,
                actionTitle: actionTitle,
                dense: dense,
                action: action
            )
        }

        private init(
            art: Art,
            title: String,
            message: String?,
            actionTitle: String?,
            dense: Bool,
            action: (() -> Void)?
        ) {
            self.art = art
            self.title = title
            self.message = message
            self.actionTitle = actionTitle
            self.dense = dense
            self.action = action
        }

        /// Error variant: a typed `WaiveraError` message (never raw server text) with Retry, on
        /// the danger tile.
        public static func error(title: String, message: String, onRetry: (() -> Void)?) -> EmptyStateView {
            EmptyStateView(
                art: .icon("exclamationmark.triangle", .danger),
                title: title,
                message: message,
                actionTitle: onRetry == nil ? nil : DesignStrings.retry,
                dense: false,
                action: onRetry
            )
        }

        public var body: some View {
            VStack(spacing: Spacing.mediumSmall) {
                switch art {
                case .icon(let systemImage, let tone):
                    IconTile(
                        systemImage: systemImage,
                        tone: tone,
                        size: ControlSize.stateIconTile,
                        glyphSize: ControlSize.stateIconGlyph
                    )
                case .illustration(let illustration):
                    IllustrationView(illustration)
                }
                Text(title)
                    .waiveraTextStyle(.titleLarge)
                    .foregroundStyle(Palette.text)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                if let actionTitle, let action {
                    WaiveraButton(actionTitle, fillsWidth: false, action: action)
                        .padding(.top, Spacing.small)
                        .accessibilityIdentifier("state.action")
                }
            }
            .padding(.horizontal, Spacing.large)
            .padding(.vertical, dense ? Spacing.small : Spacing.extraLarge)
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
            VStack(spacing: Spacing.mediumSmall) {
                BusyIndicator(size: ControlSize.progressLarge, lineWidth: ControlSize.progressStrokeLarge)
                Text(caption)
                    .waiveraTextStyle(.bodySmall)
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
                        illustration: .chats,
                        title: "No conversations yet",
                        message: "Start a chat with someone on your team.",
                        actionTitle: "New chat",
                        action: {}
                    )
                    EmptyStateView(systemImage: "magnifyingglass", title: "No matches", message: "Try another name.")
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
    #Preview("AX5") { StateGallery().dynamicTypeSize(.accessibility5) }
#endif
