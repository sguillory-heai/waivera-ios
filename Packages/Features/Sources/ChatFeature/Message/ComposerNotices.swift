#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// "Not sent" above the composer with the reason and a dismiss (03 §11): the shared error
    /// banner, as Android's `SendErrorBanner` uses `WaiveraBanner`. Silent; the model plays the
    /// one `.sendFailed` haptic.
    struct SendErrorBanner: View {
        let kind: SendErrorKind
        let noun: SendNoun
        let onDismiss: () -> Void

        var body: some View {
            BannerView(
                .error,
                title: ConversationStrings.text("not.sent"),
                message: ConversationStrings.sendError(kind, noun: noun),
                onDismiss: onDismiss
            )
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.extraSmall)
        }
    }

    /// Replaces the composer when the viewer cannot write (03 §18, 04 §1; Android
    /// `ReadOnlyNotice`): a lilac card at the composer's radius with a lock on a soft disc, read
    /// as one sentence.
    struct ReadOnlyNotice: View {
        let reason: ReadOnlyReason

        var body: some View {
            let copy = ConversationStrings.readOnly(reason)
            HStack(spacing: Spacing.mediumSmall) {
                Image(systemName: "lock.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: ControlSize.iconSmall, height: ControlSize.iconSmall)
                    .foregroundStyle(Palette.onAccentSoft)
                    .frame(width: ChatMetrics.readOnlyTile, height: ChatMetrics.readOnlyTile)
                    .background(Palette.accentWash, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(copy.title)
                        .waiveraTextStyle(.titleSmall)
                    Text(copy.reason)
                        .waiveraTextStyle(.bodySmall)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Palette.onAccentSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.mediumSmall)
            .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.composer, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.composer, style: .continuous)
                    .strokeBorder(Palette.accentBorderStrong, lineWidth: Spacing.hairline)
            )
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.small)
            .background(Palette.background)
            .accessibilityElement(children: .combine)
        }
    }

    /// The fixed-height typing slot above the composer, so the list never jumps (03 §13; Android
    /// `TypingSlot`). One line in `labelMedium`; the names give way before "is typing…" does.
    struct TypingIndicator: View {
        let label: TypingLabel?

        var body: some View {
            Group {
                if let label {
                    Text(ConversationStrings.typing(label))
                        .waiveraTextStyle(.labelMedium)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .transition(.opacity)
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: ChatMetrics.typingSlot, alignment: .leading)
            .padding(.horizontal, Spacing.gutter)
            .waiveraAnimation(.state, value: label)
        }
    }

    /// "Call in progress" strip under the header (03 §19; Android `CallBanner`), laid out above
    /// the messages so it pushes the list down. Join is a tonal button; at large text it moves
    /// under the label so neither is squeezed. The live dot is the call's, not a presence dot.
    struct CallBanner: View {
        let isOpening: Bool
        let onJoin: () -> Void

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(spacing: 0) {
                Group {
                    if dynamicTypeSize.isLargeText {
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            label
                            joinButton.frame(maxWidth: .infinity)
                        }
                    } else {
                        HStack(spacing: Spacing.small) {
                            label.frame(maxWidth: .infinity, alignment: .leading)
                            joinButton
                        }
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.small)
                .frame(minHeight: ControlSize.buttonHeight)
                .background(Palette.accentWash)
                Rectangle().fill(Palette.border).frame(height: Spacing.hairline).accessibilityHidden(true)
            }
        }

        private var label: some View {
            HStack(spacing: Spacing.small) {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: ChatMetrics.liveDot, height: ChatMetrics.liveDot)
                    .accessibilityHidden(true)
                Image(systemName: "video.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: ControlSize.iconSmall, height: ControlSize.iconSmall)
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text(ConversationStrings.text("call.in.progress"))
                    .waiveraTextStyle(.labelLarge)
                    .foregroundStyle(Palette.onAccentSoft)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }

        private var joinButton: some View {
            WaiveraButton(
                ConversationStrings.text("call.join.on.web"),
                variant: .tonal,
                systemImage: "arrow.up.right.square",
                isLoading: isOpening,
                loadingTitle: ConversationStrings.text("call.joining"),
                fillsWidth: dynamicTypeSize.isLargeText,
                action: onJoin
            )
            .fixedSize(horizontal: !dynamicTypeSize.isLargeText, vertical: false)
        }
    }
#endif
