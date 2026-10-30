#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// One-screen value primer shown once after the first sign-in, before the system prompt (09 §5,
    /// Android `NotificationPrimerScreen`). The system prompt opens only from "Turn on
    /// notifications", never on its own. "Not now" opts into quiet (provisional) delivery in the
    /// app, so nothing is lost while the person decides. Either button can be used once: a second
    /// tap cannot stack prompts.
    ///
    /// The primer's whole point is "Turn on notifications", so that button stays pinned in thumb
    /// reach at every text size. At large text two pinned buttons would crowd out the kinds, so
    /// there "Not now" moves to the end of the scrolling content instead.
    public struct NotificationPrimerView: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        private let onEnable: () -> Void
        private let onNotNow: () -> Void
        @State private var choice: Choice?

        private enum Choice {
            case enable
            case notNow
        }

        public init(onEnable: @escaping () -> Void, onNotNow: @escaping () -> Void) {
            self.onEnable = onEnable
            self.onNotNow = onNotNow
        }

        public var body: some View {
            let notNowInline = dynamicTypeSize.isLargeText
            AuthScaffold(pinnedAtLargeText: true) {
                AuthHeader(
                    systemImage: "bell.badge.fill",
                    title: AuthStrings.primerTitle,
                    message: AuthStrings.primerMessage,
                    tone: .amber,
                    welcome: true
                )
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    SampleNotification()
                    ForEach(PrimerKind.allCases, id: \.self) { kind in
                        PrimerKindRow(kind: kind)
                    }
                    Text(AuthStrings.primerFootnote)
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Spacing.extraSmall)
                    if notNowInline {
                        notNow
                    }
                }
            } actions: {
                WaiveraButton(
                    AuthStrings.primerEnable,
                    isLoading: choice == .enable,
                    loadingTitle: AuthStrings.primerRequesting
                ) {
                    choose(.enable, onEnable)
                }
                .disabled(choice == .notNow)
                .accessibilityIdentifier("primer.enable")
                if !notNowInline {
                    notNow
                }
            }
            .accessibilityIdentifier("screen.notification-primer")
        }

        private var notNow: some View {
            WaiveraButton(AuthStrings.primerNotNow, variant: .text, fillsWidth: true) {
                choose(.notNow, onNotNow)
            }
            .disabled(choice != nil)
            .accessibilityIdentifier("primer.notNow")
        }

        private func choose(_ made: Choice, _ action: () -> Void) {
            guard choice == nil else { return }
            choice = made
            action()
        }
    }

    /// A mocked notification, so the person sees what they are agreeing to. VoiceOver reads it as
    /// one example rather than as a real alert.
    private struct SampleNotification: View {
        var body: some View {
            HStack(alignment: .top, spacing: Spacing.mediumSmall) {
                WaiveraLogo(style: .mark, decorative: true)
                    .frame(height: ControlSize.icon)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(AuthStrings.primerSampleApp)
                        .waiveraTextStyle(.labelMedium)
                        .foregroundStyle(Palette.textSecondary)
                    Text(AuthStrings.primerSampleSender)
                        .waiveraTextStyle(.titleSmall)
                        .foregroundStyle(Palette.text)
                    Text(AuthStrings.primerSampleBody)
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(Palette.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.mediumSmall)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(AuthStrings.primerSampleAccessibility))
        }
    }

    /// One kind: its meaning tile, title and explanation, read together as one VoiceOver stop.
    private struct PrimerKindRow: View {
        let kind: PrimerKind

        var body: some View {
            HStack(alignment: .top, spacing: Spacing.mediumSmall) {
                IconTile(systemImage: kind.systemImage, tone: kind.tone)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(kind.title)
                        .waiveraTextStyle(.titleSmall)
                        .foregroundStyle(Palette.text)
                    Text(kind.detail)
                        .waiveraTextStyle(.bodyMedium)
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
    #Preview("AX5") { NotificationPrimerView(onEnable: {}, onNotNow: {}).dynamicTypeSize(.accessibility5) }
#endif
