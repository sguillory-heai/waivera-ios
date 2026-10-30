#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// A settings page: the eyebrow sections and their cards on the page colour, scrolling under
    /// the system navigation bar (Android `SettingsContent`).
    struct SettingsPage<Content: View>: View {
        @ViewBuilder let content: Content

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.large)
                .frame(maxWidth: ControlSize.sheetMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.background)
        }
    }

    /// A row that navigates from its action: tile, title, subtitle and chevron. Rows navigate
    /// from their action, never a pressable nested in a link (11-pitfalls #46).
    struct SettingsLinkRow: View {
        let title: String
        let subtitle: String?
        let systemImage: String
        var tone: TileTone = .brand
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                ListRow(title: title, subtitle: subtitle, showsChevron: true) {
                    IconTile(systemImage: systemImage, tone: tone)
                }
            }
            .buttonStyle(.press(.row))
            .accessibilityAddTraits(.isButton)
        }
    }

    /// A switch row with its meaning tile (Android `WaiveraSwitchRow`). The whole row flips the
    /// switch; VoiceOver hears one toggle with its title, subtitle and state. No haptic: the
    /// switch's own motion answers. A blocked row is dimmed and its tile goes neutral, and it
    /// keeps its stored value.
    struct SettingsToggleRow: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let title: String
        let subtitle: String?
        let systemImage: String
        var tone: TileTone = .brand
        var isEnabled = true
        let isOn: Bool
        let onChange: (Bool) -> Void

        var body: some View {
            Button {
                flip()
            } label: {
                ListRow(title: title, subtitle: subtitle) {
                    IconTile(systemImage: systemImage, tone: isEnabled ? tone : .neutral)
                } trailing: {
                    Toggle(isOn: .constant(isOn)) { EmptyView() }
                        .labelsHidden()
                        .tint(Palette.accentFill)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.press(.row))
            .opacity(isEnabled ? 1 : Emphasis.disabled)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
            .accessibilityHint(subtitle.map { Text($0) } ?? Text(verbatim: ""))
            .accessibilityValue(Text(isOn ? SettingsStrings.on : SettingsStrings.off))
            .accessibilityAddTraits(.isToggle)
            .accessibilityAction { flip() }
            .accessibilityRespondsToUserInteraction(isEnabled)
            // After the accessibility element, so VoiceOver hears the row as dimmed too and its
            // default action is covered, not only the button inside it.
            .disabled(!isEnabled)
        }

        /// A blocked row keeps its stored value, whichever way the flip arrives.
        private func flip() {
            guard isEnabled else { return }
            withAnimation(Motion.animation(.state, reduceMotion: reduceMotion)) { onChange(!isOn) }
        }
    }

    /// A single-choice row: a leading radio, title and subtitle (Android `SettingsRadioRow`).
    /// Spoken as a selected or unselected button; picking never vibrates. The radio's dot pops in.
    struct SettingsRadioRow: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let title: String
        let subtitle: String?
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                ListRow(title: title, subtitle: subtitle) {
                    RadioMark(isSelected: isSelected)
                }
            }
            .buttonStyle(.press(.row))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .animation(Motion.animation(.state, reduceMotion: reduceMotion), value: isSelected)
        }
    }

    private struct RadioMark: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let isSelected: Bool

        var body: some View {
            ZStack {
                Circle()
                    .strokeBorder(isSelected ? Palette.accent : Palette.textSecondary, lineWidth: Spacing.xxSmall)
                if isSelected {
                    Circle()
                        .fill(Palette.accent)
                        .padding(Spacing.small - Spacing.xxSmall)
                        .transition(Motion.pop(reduceMotion: reduceMotion))
                }
            }
            .frame(width: ControlSize.icon, height: ControlSize.icon)
            .frame(width: ControlSize.iconTile, height: ControlSize.iconTile)
            .accessibilityHidden(true)
        }
    }

    /// The hairline between rows on one card, inset past the tile.
    struct SettingsRowDivider: View {
        var body: some View {
            Rectangle()
                .fill(Palette.border)
                .frame(height: Spacing.hairline)
                .padding(.leading, Spacing.medium + ControlSize.iconTile + Spacing.mediumSmall)
                .accessibilityHidden(true)
        }
    }

    /// A short explanation between a section header and its card.
    struct SettingsNote: View {
        let text: String

        var body: some View {
            Text(text)
                .waiveraTextStyle(.bodySmall)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.medium)
                .padding(.bottom, Spacing.small)
        }
    }

    private struct SettingsComponentsGallery: View {
        @State private var isOn = true
        @State private var choice = 0

        var body: some View {
            SettingsPage {
                SectionHeader("Preferences")
                CardGroup {
                    SettingsLinkRow(
                        title: "Notifications",
                        subtitle: "Messages",
                        systemImage: "bell.fill",
                        tone: .amber
                    ) {}
                    SettingsRowDivider()
                    SettingsToggleRow(
                        title: "Haptics",
                        subtitle: "One short vibration when a message fails to send.",
                        systemImage: "iphone.radiowaves.left.and.right",
                        tone: .rose,
                        isOn: isOn
                    ) { isOn = $0 }
                    SettingsRowDivider()
                    SettingsRadioRow(title: "System", subtitle: "Match your device", isSelected: choice == 0) {
                        choice = 0
                    }
                    SettingsRowDivider()
                    SettingsRadioRow(title: "Dark", subtitle: nil, isSelected: choice == 1) { choice = 1 }
                }
            }
        }
    }

    #Preview("Light") { SettingsComponentsGallery() }
    #Preview("Dark") { SettingsComponentsGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { SettingsComponentsGallery().dynamicTypeSize(.accessibility5) }
#endif
