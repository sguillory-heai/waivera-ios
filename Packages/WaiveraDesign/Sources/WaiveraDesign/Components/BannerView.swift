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

    /// Full-width inset card with an icon, a message, an optional action and an optional dismiss.
    public struct BannerView: View {
        private let kind: BannerKind
        private let message: String
        private let actionTitle: String?
        private let action: (() -> Void)?
        private let onDismiss: (() -> Void)?

        public init(
            _ kind: BannerKind,
            message: String,
            actionTitle: String? = nil,
            action: (() -> Void)? = nil,
            onDismiss: (() -> Void)? = nil
        ) {
            self.kind = kind
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
            HStack(spacing: Spacing.smallPlus) {
                Image(systemName: systemImage)
                    .font(WaiveraFont.bodyEmphasis)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(message)
                    .font(WaiveraFont.caption)
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(WaiveraFont.label)
                        .foregroundStyle(Palette.accent)
                        .frame(minWidth: ControlSize.minHitTarget, minHeight: ControlSize.minHitTarget)
                        .accessibilityIdentifier("banner.action")
                }
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(WaiveraFont.captionEmphasis)
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(DesignStrings.dismiss))
                }
            }
            .padding(.leading, Spacing.medium)
            .padding(.trailing, Spacing.small)
            .padding(.vertical, Spacing.extraSmall)
            .frame(minHeight: ControlSize.buttonHeight)
            .background(Palette.surface, in: shape)
            .background(tint.opacity(Emphasis.bannerWash), in: shape)
            .overlay(shape.strokeBorder(tint.opacity(Emphasis.bannerBorder), lineWidth: Spacing.hairline))
            .accessibilityElement(children: .contain)
        }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        }

        private var systemImage: String {
            switch kind {
            case .offline: "wifi.slash"
            case .reconnecting: "arrow.triangle.2.circlepath"
            case .error: "exclamationmark.triangle.fill"
            case .info: "bell.fill"
            case .readOnly: "lock.fill"
            }
        }

        private var tint: Color {
            switch kind {
            case .offline, .reconnecting: Palette.warning
            case .error: Palette.danger
            case .info: Palette.accent
            case .readOnly: Palette.textSecondary
            }
        }
    }

    private struct BannerGallery: View {
        var body: some View {
            VStack(spacing: Spacing.smallPlus) {
                BannerView.offline {}
                BannerView.reconnecting {}
                BannerView(.error, message: "Message not sent.", actionTitle: "Retry", action: {}, onDismiss: {})
                BannerView(.info, message: "Alex Rivera: can you cover Friday?", onDismiss: {})
                BannerView(.readOnly, message: "Only admins can post in this channel.")
            }
            .padding(Spacing.medium)
            .background(Palette.background)
        }
    }

    #Preview("Light") { BannerGallery() }
    #Preview("Dark") { BannerGallery().preferredColorScheme(.dark) }
    #Preview("AX XXXL") { BannerGallery().dynamicTypeSize(.accessibility5) }
#endif
