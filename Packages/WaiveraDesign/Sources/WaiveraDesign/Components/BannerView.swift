#if canImport(UIKit)
    import SwiftUI

    public enum BannerKind: Sendable {
        /// No network; changes queue in the outbox.
        case offline
        /// The hub is reconnecting.
        case reconnecting
        /// Something failed; the message says what to do next.
        case error
        /// An in-app notification or neutral information.
        case info
        /// The conversation cannot be written to.
        case readOnly
    }

    /// A full-width tinted banner (Android `WaiveraBanner`): an icon, an optional title, the
    /// message, and an optional text action and dismiss. The icon and buttons stay level with the
    /// first line of a wrapped message. The action moves under the text when it would squeeze the
    /// message, and at large text with a dismiss both go in a row under it (`BannerLayoutRule`).
    /// Announced politely when it appears.
    public struct BannerView: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        private let kind: BannerKind
        private let title: String?
        private let message: String
        private let actionTitle: String?
        private let action: (() -> Void)?
        private let onDismiss: (() -> Void)?

        public init(
            _ kind: BannerKind,
            title: String? = nil,
            message: String,
            actionTitle: String? = nil,
            action: (() -> Void)? = nil,
            onDismiss: (() -> Void)? = nil
        ) {
            self.kind = kind
            self.title = title
            self.message = message
            self.actionTitle = actionTitle
            self.action = action
            self.onDismiss = onDismiss
        }

        /// Offline banner with Retry.
        public static func offline(onRetry: @escaping () -> Void) -> BannerView {
            BannerView(.offline, message: DesignStrings.offline, actionTitle: DesignStrings.retry, action: onRetry)
        }

        /// Reconnecting banner with a manual Retry (reconnect never gives up, 11-pitfalls #11).
        public static func reconnecting(onRetry: @escaping () -> Void) -> BannerView {
            BannerView(
                .reconnecting,
                message: DesignStrings.reconnecting,
                actionTitle: DesignStrings.retry,
                action: onRetry
            )
        }

        public var body: some View {
            Group {
                if hasAction && onDismiss != nil && dynamicTypeSize.isLargeText {
                    VStack(alignment: .trailing, spacing: 0) {
                        row(inlineAction: false, inlineDismiss: false)
                        HStack(spacing: 0) {
                            actionButton
                            dismissButton
                        }
                    }
                } else if hasAction {
                    ViewThatFits(in: .horizontal) {
                        row(inlineAction: true, inlineDismiss: true)
                        VStack(alignment: .trailing, spacing: 0) {
                            row(inlineAction: false, inlineDismiss: true)
                            actionButton
                        }
                    }
                } else {
                    row(inlineAction: false, inlineDismiss: true)
                }
            }
            .padding(.leading, Spacing.mediumSmall)
            .padding(.trailing, onDismiss == nil && !hasAction ? Spacing.mediumSmall : 0)
            .padding(.vertical, Spacing.extraSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(container, in: RoundedRectangle(cornerRadius: Radius.banner, style: .continuous))
            .accessibilityElement(children: .contain)
        }

        private var hasAction: Bool { actionTitle != nil && action != nil }

        private func row(inlineAction: Bool, inlineDismiss: Bool) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.mediumSmall) {
                Image(systemName: systemImage)
                    .font(.system(size: ControlSize.icon * 0.8))
                    .foregroundStyle(ink)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    if let title {
                        Text(title)
                            .waiveraTextStyle(.titleSmall)
                    }
                    Text(message)
                        .waiveraTextStyle(.bodySmall)
                }
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Spacing.mediumSmall)
                if inlineAction {
                    actionButton
                }
                if inlineDismiss {
                    dismissButton
                }
            }
        }

        @ViewBuilder private var actionButton: some View {
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .waiveraTextStyle(.labelLarge)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, Spacing.mediumSmall)
                        .frame(minWidth: ControlSize.minHitTarget, minHeight: ControlSize.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press(.compact))
                .accessibilityIdentifier("banner.action")
            }
        }

        @ViewBuilder private var dismissButton: some View {
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(WaiveraFont.captionEmphasis)
                        .foregroundStyle(ink)
                        .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press(.compact))
                .accessibilityLabel(Text(DesignStrings.dismiss))
            }
        }

        private var systemImage: String {
            switch kind {
            case .offline: "icloud.slash"
            case .reconnecting: "arrow.triangle.2.circlepath"
            case .error: "exclamationmark.circle"
            case .info: "info.circle"
            case .readOnly: "lock"
            }
        }

        private var container: Color {
            switch kind {
            case .info: Palette.accentSoft
            case .reconnecting: Palette.warningContainer
            case .error: Palette.dangerContainer
            case .offline, .readOnly: Palette.surfaceMuted
            }
        }

        private var ink: Color {
            switch kind {
            case .info: Palette.onAccentSoft
            case .reconnecting: Palette.onWarningContainer
            case .error: Palette.onDangerContainer
            case .offline: Palette.text
            case .readOnly: Palette.textSecondary
            }
        }
    }

    private struct BannerGallery: View {
        var body: some View {
            ScrollView {
                VStack(spacing: Spacing.mediumSmall) {
                    BannerView.offline {}
                    BannerView.reconnecting {}
                    BannerView(.error, message: "Message not sent.", actionTitle: "Retry", action: {}, onDismiss: {})
                    BannerView(.info, title: "Alex Rivera", message: "Can you cover Friday?", onDismiss: {})
                    BannerView(.readOnly, message: "Only admins can post in this channel.")
                }
                .padding(Spacing.medium)
            }
            .background(Palette.background)
        }
    }

    #Preview("Light") { BannerGallery() }
    #Preview("Dark") { BannerGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { BannerGallery().dynamicTypeSize(.accessibility5) }
#endif
