#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// "Not sent" above the composer with the reason and a dismiss (03 §11).
    struct SendErrorBanner: View {
        let kind: SendErrorKind
        let noun: SendNoun
        let onDismiss: () -> Void

        var body: some View {
            HStack(alignment: .top, spacing: Spacing.smallPlus) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Palette.danger)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(ConversationStrings.text("not.sent"))
                        .font(WaiveraFont.captionEmphasis)
                        .foregroundStyle(Palette.text)
                    Text(ConversationStrings.sendError(kind, noun: noun))
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                }
                .accessibilityLabel(ConversationStrings.text("dismiss.send.error"))
            }
            .padding(.leading, Spacing.smallPlus)
            .padding(.vertical, Spacing.extraSmall)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.danger, lineWidth: Spacing.hairline)
            )
            .padding(.horizontal, Spacing.medium)
            .accessibilityElement(children: .contain)
        }
    }

    /// Replaces the composer when the viewer cannot write (03 §18, 04 §1).
    struct ReadOnlyNotice: View {
        let reason: ReadOnlyReason

        var body: some View {
            let copy = ConversationStrings.readOnly(reason)
            HStack(alignment: .top, spacing: Spacing.smallPlus) {
                Image(systemName: reason == .automated ? "sparkles" : "lock.fill")
                    .font(WaiveraFont.caption)
                    .foregroundStyle(Palette.accent)
                    .frame(width: ChatMetrics.readOnlyTile, height: ChatMetrics.readOnlyTile)
                    .background(Palette.accentWash, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(copy.title).font(WaiveraFont.subtitle).foregroundStyle(Palette.text)
                    Text(copy.reason)
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Spacing.smallPlus)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
            )
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .background(Palette.background)
            .accessibilityElement(children: .combine)
        }
    }

    /// The fixed-height typing slot above the composer, so the list never jumps (03 §13).
    struct TypingIndicator: View {
        let label: TypingLabel?

        var body: some View {
            Group {
                if let label {
                    Text(ConversationStrings.typing(label))
                        .font(WaiveraFont.caption.italic())
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .transition(.opacity)
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: ChatMetrics.typingSlot, alignment: .leading)
            .padding(.horizontal, Spacing.medium)
            .waiveraAnimation(.state, value: label)
        }
    }

    /// "Call in progress · Join on web ›" under the header (03 §19).
    struct CallBanner: View {
        let isOpening: Bool
        let onJoin: () -> Void

        var body: some View {
            Button(action: onJoin) {
                HStack(spacing: Spacing.small) {
                    Circle().fill(Palette.success).frame(width: ChatMetrics.liveDot, height: ChatMetrics.liveDot)
                        .accessibilityHidden(true)
                    Text(ConversationStrings.text("call.in.progress"))
                        .font(WaiveraFont.captionEmphasis)
                        .foregroundStyle(Palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isOpening {
                        ProgressView()
                    } else {
                        Text(ConversationStrings.text("call.join.on.web"))
                            .font(WaiveraFont.captionEmphasis)
                            .foregroundStyle(Palette.accent)
                    }
                }
                .padding(.horizontal, Spacing.medium)
                .frame(minHeight: ControlSize.buttonHeight)
                .background(Palette.accentWash)
            }
            .buttonStyle(.pressScale)
            .disabled(isOpening)
            .accessibilityElement(children: .combine)
        }
    }
#endif
