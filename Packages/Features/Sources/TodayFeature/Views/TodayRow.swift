#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// One tappable Today row: a leading tile or avatar, an optional eyebrow, the headline, a
    /// supporting line and a trailing badge. Rows grow with Dynamic Type; nothing truncates.
    /// VoiceOver reads one combined label and the hint says where the row leads.
    struct TodayRow<Leading: View, Trailing: View>: View {
        var eyebrow: String?
        var eyebrowTint: Color = Palette.textSecondary
        let headline: String
        var supporting: String?
        var emphasized = false
        var showsChevron = false
        let accessibilityText: String
        let accessibilityHintText: String
        let action: () -> Void
        @ViewBuilder let leading: () -> Leading
        @ViewBuilder let trailing: () -> Trailing

        var body: some View {
            Button(action: action) {
                HStack(alignment: .center, spacing: Spacing.smallPlus) {
                    leading()
                    VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                        if let eyebrow {
                            Text(eyebrow)
                                .font(WaiveraFont.captionEmphasis)
                                .foregroundStyle(eyebrowTint)
                        }
                        Text(headline)
                            .font(emphasized ? WaiveraFont.bodyEmphasis : WaiveraFont.body)
                            .foregroundStyle(Palette.text)
                        if let supporting, !supporting.isEmpty {
                            Text(supporting)
                                .font(WaiveraFont.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    trailing()
                    if showsChevron {
                        Image(systemName: "chevron.right")
                            .font(WaiveraFont.captionEmphasis)
                            .foregroundStyle(Palette.textSecondary)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.smallPlus)
                .frame(minHeight: ControlSize.minHitTarget)
                .background(emphasized ? Palette.accentWash : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressScale)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityText))
            .accessibilityHint(Text(accessibilityHintText))
            .accessibilityAddTraits(.isButton)
        }
    }

    extension TodayRow where Trailing == EmptyView {
        init(
            eyebrow: String? = nil,
            eyebrowTint: Color = Palette.textSecondary,
            headline: String,
            supporting: String? = nil,
            emphasized: Bool = false,
            showsChevron: Bool = false,
            accessibilityText: String,
            accessibilityHintText: String,
            action: @escaping () -> Void,
            @ViewBuilder leading: @escaping () -> Leading
        ) {
            self.init(
                eyebrow: eyebrow,
                eyebrowTint: eyebrowTint,
                headline: headline,
                supporting: supporting,
                emphasized: emphasized,
                showsChevron: showsChevron,
                accessibilityText: accessibilityText,
                accessibilityHintText: accessibilityHintText,
                action: action,
                leading: leading,
                trailing: { EmptyView() }
            )
        }
    }

    /// A section title with an optional trailing control. It wraps under the title at large
    /// text sizes instead of squeezing.
    struct TodaySectionHeader<Trailing: View>: View {
        let title: String
        @ViewBuilder let trailing: () -> Trailing

        var body: some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.small) {
                    titleText
                    Spacer(minLength: Spacing.small)
                    trailing()
                }
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    titleText
                    HStack(spacing: Spacing.small) { trailing() }
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.top, Spacing.large)
            .padding(.bottom, Spacing.extraSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var titleText: some View {
            Text(title)
                .font(WaiveraFont.sectionTitle)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
        }
    }

    extension TodaySectionHeader where Trailing == EmptyView {
        init(title: String) {
            self.init(title: title, trailing: { EmptyView() })
        }
    }

    /// A text-only action in a section header, with a 44pt hit target.
    struct TodayTextButton: View {
        let title: String
        var systemImage: String?
        var hint: String?
        var isLoading = false
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                ZStack {
                    label.opacity(isLoading ? 0 : 1)
                    if isLoading {
                        ProgressView().tint(Palette.accent)
                    }
                }
                .font(WaiveraFont.label)
                .foregroundStyle(Palette.accent)
                .frame(minWidth: ControlSize.minHitTarget, minHeight: ControlSize.minHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressScale)
            .disabled(isLoading)
            .accessibilityHint(hint.map { Text($0) } ?? Text(verbatim: ""))
        }

        @ViewBuilder private var label: some View {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
    }
#endif
