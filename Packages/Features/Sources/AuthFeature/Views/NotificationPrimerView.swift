#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// One-screen value primer shown once after the first sign-in, before the system prompt (09 §5,
    /// UX research). The system prompt opens only from "Turn on notifications", never on its own.
    /// "Not now" opts into quiet (provisional) delivery in the app, so nothing is lost while the
    /// person decides. Either button can be used once: a second tap cannot stack prompts.
    public struct NotificationPrimerView: View {
        private let onEnable: () -> Void
        private let onNotNow: () -> Void
        @State private var hasChosen = false

        public init(onEnable: @escaping () -> Void, onNotNow: @escaping () -> Void) {
            self.onEnable = onEnable
            self.onNotNow = onNotNow
        }

        public var body: some View {
            AuthScaffold {
                AuthHeader(
                    systemImage: "bell.badge.fill",
                    title: AuthStrings.primerTitle,
                    message: AuthStrings.primerMessage
                )
                SampleNotification()
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    ForEach(PrimerCategory.allCases, id: \.self) { category in
                        PrimerCategoryRow(category: category)
                    }
                }
                Text(AuthStrings.primerFootnote)
                    .font(WaiveraFont.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: Spacing.small) {
                    WaiveraButton(AuthStrings.primerEnable, isLoading: hasChosen) {
                        choose(onEnable)
                    }
                    .accessibilityIdentifier("primer.enable")
                    WaiveraButton(AuthStrings.primerNotNow, variant: .plain) {
                        choose(onNotNow)
                    }
                    .disabled(hasChosen)
                    .accessibilityIdentifier("primer.notNow")
                }
            }
            .accessibilityIdentifier("screen.notification-primer")
        }

        private func choose(_ action: () -> Void) {
            guard !hasChosen else { return }
            hasChosen = true
            action()
        }
    }

    private struct SampleNotification: View {
        var body: some View {
            HStack(alignment: .top, spacing: Spacing.smallPlus) {
                AvatarView(name: AuthStrings.primerSampleSender, size: ControlSize.avatarSmall)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(AuthStrings.primerSampleAccessibility))
        }
    }

    private struct PrimerCategoryRow: View {
        let category: PrimerCategory

        var body: some View {
            HStack(alignment: .top, spacing: Spacing.smallPlus) {
                Image(systemName: category.systemImage)
                    .font(WaiveraFont.bodyEmphasis)
                    .foregroundStyle(Palette.accent)
                    .frame(minWidth: ControlSize.smallIcon)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    Text(category.title)
                        .font(WaiveraFont.bodyEmphasis)
                        .foregroundStyle(Palette.text)
                    Text(category.detail)
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    #Preview("Light") { NotificationPrimerView(onEnable: {}, onNotNow: {}) }
    #Preview("Dark") { NotificationPrimerView(onEnable: {}, onNotNow: {}).preferredColorScheme(.dark) }
    #Preview("AX XXXL") { NotificationPrimerView(onEnable: {}, onNotNow: {}).dynamicTypeSize(.accessibility5) }
#endif
