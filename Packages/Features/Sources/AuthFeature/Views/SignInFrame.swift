#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// The sign-in frame (Android `SignInFrame`): the plum brand header full bleed behind the
    /// status bar, and the curved sheet rising over it with the form. One scroll holds both, so at
    /// AX sizes everything is reachable, and the scroll keeps the focused field above the keyboard.
    ///
    /// The header drops to its compact height while `compact` (a field has focus, so the keyboard
    /// is up), on a short window or at large text, so the form starts high. `footer` sits at the
    /// bottom of the sheet when everything fits and follows the form when it does not.
    ///
    /// On first show the sheet rises and fades in and the logo fades in; under Reduce Motion both
    /// are simply there, and the entrance never replays.
    struct SignInFrame<Content: View, Footer: View>: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private let compact: Bool
        private let content: Content
        private let footer: Footer
        @State private var entered = false

        init(compact: Bool, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
            self.compact = compact
            self.content = content()
            self.footer = footer()
        }

        var body: some View {
            GeometryReader { proxy in
                let topInset = proxy.safeAreaInsets.top
                let window = Double(proxy.size.height + topInset + proxy.safeAreaInsets.bottom)
                let isCompact = compact || dynamicTypeSize.isLargeText || HeroMetrics.isShortWindow(height: window)
                let header = CGFloat(HeroMetrics.signInHeaderHeight(windowHeight: window, compact: isCompact))
                ScrollView {
                    ZStack(alignment: .top) {
                        SignInHeader(topInset: topInset, height: header, compact: isCompact, shown: shown)
                        sheet(minHeight: max(0, proxy.size.height - header))
                            .padding(.top, topInset + header)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
                .ignoresSafeArea(.container, edges: .top)
                .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: isCompact)
            }
            .background(HeroPalette.sheet)
            .onAppear {
                guard !entered else { return }
                if reduceMotion {
                    entered = true
                } else {
                    withAnimation(Motion.animation(.layout, reduceMotion: false)) { entered = true }
                }
            }
        }

        private var shown: Bool { entered || reduceMotion }

        private func sheet(minHeight: CGFloat) -> some View {
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: CGFloat(HeroMetrics.sheetCornerSignIn),
                topTrailingRadius: CGFloat(HeroMetrics.sheetCornerSignIn),
                style: .continuous
            )
            return VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    content
                }
                .frame(maxWidth: ControlSize.sheetMaxWidth)
                // Fills up to the sheet's minimum height only: the footer sits at the bottom when
                // the form is short and follows it otherwise.
                Spacer(minLength: 0)
                footer
                    .frame(maxWidth: ControlSize.sheetMaxWidth)
                    .padding(.top, Spacing.large)
            }
            // Concept A: 32 above "Welcome back" and 24 at the sides.
            .padding(.top, compact ? Spacing.mediumPlus : Spacing.extraLarge)
            .padding(.bottom, Spacing.medium)
            .padding(.horizontal, Spacing.large)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .top)
            .background(HeroPalette.sheet, in: shape)
            .offset(y: shown ? 0 : CGFloat(HeroMetrics.entranceRise))
            .opacity(shown ? 1 : 0)
        }
    }

    /// The header `height` tall below the `topInset`, drawn under the sheet's curve too so the
    /// corners show plum. The regular lockup's middle sits at 42% of the header; the compact one
    /// is centred.
    private struct SignInHeader: View {
        let topInset: CGFloat
        let height: CGFloat
        let compact: Bool
        let shown: Bool

        var body: some View {
            let lockup = CGFloat(compact ? HeroMetrics.lockupCompact : HeroMetrics.lockup)
            HeroBackdrop(trail: .signIn)
                .frame(height: topInset + height + CGFloat(HeroMetrics.sheetOverlap))
                .overlay(alignment: .top) {
                    WaiveraLogo(style: .lockup, ink: HeroPalette.onHeader)
                        .frame(height: lockup)
                        .frame(maxWidth: .infinity)
                        .padding(
                            .top,
                            topInset
                                + (compact
                                    ? (height - lockup) / 2 : height * HeroMetrics.lockupCenterShare - lockup / 2)
                        )
                        .opacity(shown ? 1 : 0)
                }
        }
    }

    /// "By continuing, you agree to our Terms of Service and Privacy Policy." as one typeset
    /// sentence (Android `LegalFooter`, UI9-03): every word is its own item in one flow, so it
    /// wraps where text would. "our" travels with the Terms link and the full stop with Privacy
    /// Policy, so neither is left alone on a line. Each name is a link whose target reaches 44pt
    /// tall without spreading the lines apart; it opens the page in the browser.
    struct LegalFooter: View {
        let links: LegalLinks
        let onOpen: (URL) -> Void

        var body: some View {
            WordFlowLayout(spacing: Spacing.extraSmall, lineSpacing: Spacing.xxSmall) {
                ForEach(Array(leadWords.enumerated()), id: \.offset) { index, word in
                    // VoiceOver reads the lead once, as a sentence, not word by word.
                    if index == 0 {
                        Text(word).accessibilityLabel(Text(AuthStrings.legalLead))
                    } else {
                        Text(word).accessibilityHidden(true)
                    }
                }
                HStack(spacing: Spacing.extraSmall) {
                    Text(AuthStrings.legalTermsLead)
                        .accessibilityHidden(true)
                    LegalLink(title: AuthStrings.legalTerms) { onOpen(links.termsOfService) }
                }
                Text(AuthStrings.legalAnd)
                    .accessibilityHidden(true)
                HStack(spacing: 0) {
                    LegalLink(title: AuthStrings.legalPrivacy) { onOpen(links.privacyPolicy) }
                    Text(AuthStrings.legalEnd)
                        .accessibilityHidden(true)
                }
            }
            .waiveraTextStyle(.bodySmall)
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, Spacing.extraSmall)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("signIn.legal")
        }

        private var leadWords: [String] {
            AuthStrings.legalLead.split(separator: " ").map(String.init)
        }
    }

    /// One legal link: the underlined accent name, with a 44pt tall hit area that overlaps the
    /// lines above and below instead of spreading the sentence apart.
    private struct LegalLink: View {
        let title: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Text(title)
                    .underline()
                    .foregroundStyle(Palette.link)
                    .contentShape(Rectangle().inset(by: -LegalLink.slack))
            }
            .buttonStyle(.press(.compact))
            .accessibilityAddTraits(.isLink)
            .accessibilityHint(Text(AuthStrings.legalOpenHint))
        }

        /// How far the hit area reaches past the text on each side, so a ~18pt line is a 44pt target.
        private static let slack = (ControlSize.minHitTarget - Spacing.medium - Spacing.xxSmall) / 2
    }

    /// Lays its children out like words in a paragraph: left to right, wrapping to a new line
    /// when the next one does not fit, each line centred.
    struct WordFlowLayout: Layout {
        let spacing: CGFloat
        let lineSpacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
            let lines = arrange(width: proposal.width ?? .infinity, subviews: subviews)
            let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, lines.count - 1))
            let width = lines.map(\.width).max() ?? 0
            return CGSize(width: proposal.width ?? width, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
            var y = bounds.minY
            for line in arrange(width: bounds.width, subviews: subviews) {
                var x = bounds.minX + (bounds.width - line.width) / 2
                for index in line.indices {
                    let size = subviews[index].sizeThatFits(.unspecified)
                    subviews[index].place(
                        at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                        proposal: ProposedViewSize(size)
                    )
                    x += size.width + spacing
                }
                y += line.height + lineSpacing
            }
        }

        private struct Line {
            var indices: [Int] = []
            var width: CGFloat = 0
            var height: CGFloat = 0
        }

        private func arrange(width: CGFloat, subviews: Subviews) -> [Line] {
            var lines: [Line] = []
            var current = Line()
            for index in subviews.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let added = current.indices.isEmpty ? size.width : current.width + spacing + size.width
                if added > width, !current.indices.isEmpty {
                    lines.append(current)
                    current = Line()
                }
                current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
                current.height = max(current.height, size.height)
                current.indices.append(index)
            }
            if !current.indices.isEmpty { lines.append(current) }
            return lines
        }
    }
#endif
