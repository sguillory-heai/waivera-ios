import SwiftUI
import WaiveraDesign

/// One-screen value primer shown once after first sign-in, before the system prompt
/// (UX research). "Turn on notifications" asks for full permission; "Not now" opts into quiet
/// (provisional) delivery so nothing is lost while the person decides.
public struct NotificationPrimerView: View {
    private let onEnable: () -> Void
    private let onNotNow: () -> Void

    public init(onEnable: @escaping () -> Void, onNotNow: @escaping () -> Void) {
        self.onEnable = onEnable
        self.onNotNow = onNotNow
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                Text(AuthStrings.primerTitle)
                    .font(WaiveraFont.screenTitle)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                SampleNotification()
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    PrimerReason(systemImage: "bubble.left.and.bubble.right.fill", text: AuthStrings.primerMessages)
                    PrimerReason(systemImage: "checklist", text: AuthStrings.primerAssignments)
                    PrimerReason(systemImage: "calendar", text: AuthStrings.primerSchedule)
                }
                Text(AuthStrings.primerFootnote)
                    .font(WaiveraFont.caption)
                    .foregroundStyle(Palette.textSecondary)
                VStack(spacing: Spacing.small) {
                    WaiveraButton(AuthStrings.primerEnable, action: onEnable)
                        .accessibilityIdentifier("primer.enable")
                    WaiveraButton(AuthStrings.primerNotNow, variant: .plain, action: onNotNow)
                        .accessibilityIdentifier("primer.notNow")
                }
            }
            .padding(Spacing.large)
        }
        .background(Palette.background)
        .accessibilityIdentifier("screen.notification-primer")
    }
}

private struct SampleNotification: View {
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.smallPlus) {
            AvatarView(name: AuthStrings.primerSampleSender, size: ControlSize.avatarSmall, rounded: true)
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(AuthStrings.primerSampleSender)
                    .font(WaiveraFont.captionEmphasis)
                    .foregroundStyle(Palette.text)
                Text(AuthStrings.primerSampleBody)
                    .font(WaiveraFont.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.smallPlus)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(AuthStrings.primerSampleAccessibility))
    }
}

private struct PrimerReason: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.smallPlus) {
            Image(systemName: systemImage)
                .font(WaiveraFont.bodyEmphasis)
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text(text)
                .font(WaiveraFont.body)
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Light") { NotificationPrimerView(onEnable: {}, onNotNow: {}) }
#Preview("Dark") { NotificationPrimerView(onEnable: {}, onNotNow: {}).preferredColorScheme(.dark) }
#Preview("AX XXXL") { NotificationPrimerView(onEnable: {}, onNotNow: {}).dynamicTypeSize(.accessibility5) }
