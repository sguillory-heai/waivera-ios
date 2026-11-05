#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// The server's password rules under the new-password field, ticked off while the person
    /// types (the web and Android show the same list). `showsUnmet` colours the open rules as
    /// errors once a submit was refused for them.
    struct PasswordRulesChecklist: View {
        let lines: [PasswordRuleLine]
        let showsUnmet: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(AuthStrings.passwordRulesTitle)
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(lines) { line in
                    PasswordRuleRow(line: line, showsUnmet: showsUnmet)
                }
            }
        }
    }

    private struct PasswordRuleRow: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let line: PasswordRuleLine
        let showsUnmet: Bool

        private var color: Color {
            if line.isMet { return Palette.successText }
            return showsUnmet ? Palette.dangerText : Palette.textSecondary
        }

        var body: some View {
            HStack(spacing: Spacing.small) {
                ZStack {
                    if line.isMet {
                        WaiveraIcon(systemName: "checkmark", pointSize: ControlSize.iconSmall)
                            .foregroundStyle(Palette.successText)
                            .transition(.opacity)
                    } else {
                        Circle()
                            .fill(color)
                            .frame(width: ControlSize.iconSmall / 2, height: ControlSize.iconSmall / 2)
                            .transition(.opacity)
                    }
                }
                .frame(width: ControlSize.iconSmall, height: ControlSize.iconSmall)
                Text(line.label)
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .animation(Motion.animation(.state, reduceMotion: reduceMotion), value: line.isMet)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line.spokenLabel)
        }
    }
#endif
