#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Full-screen frame for the gate screens (Android `AuthScaffold`). The screen opens on the
    /// compact plum hero with the Waivera lockup, drawn behind the status bar, and the content sits
    /// on the page sheet that curves over it, so the screens after sign-in carry on from sign-in.
    /// The hero shrinks to a band at large text, on a short window and while `compactHero` (a
    /// field has focus, so the keyboard is up).
    ///
    /// `actions` are the screen's primary actions, pinned at the bottom in thumb reach with the
    /// content scrolling above them. At large text they follow the content instead, unless
    /// `pinnedAtLargeText` keeps them pinned there too. The scroll view is the single keyboard
    /// owner (11-pitfalls #31): it moves the focused field above the keyboard and dismisses it on
    /// drag. Content is width-capped so it stays readable on an iPad.
    struct AuthScaffold<Content: View, Actions: View>: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private let showsHero: Bool
        private let compactHero: Bool
        private let pinnedAtLargeText: Bool
        private let content: Content
        private let actions: Actions

        /// `showsHero` is false under a navigation bar (the voluntary password change).
        init(
            showsHero: Bool = true,
            compactHero: Bool = false,
            pinnedAtLargeText: Bool = false,
            @ViewBuilder content: () -> Content,
            @ViewBuilder actions: () -> Actions
        ) {
            self.showsHero = showsHero
            self.compactHero = compactHero
            self.pinnedAtLargeText = pinnedAtLargeText
            self.content = content()
            self.actions = actions()
        }

        var body: some View {
            GeometryReader { proxy in
                let window = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
                let band =
                    compactHero || dynamicTypeSize.isLargeText || HeroMetrics.isShortWindow(height: Double(window))
                let actionsInline = dynamicTypeSize.isLargeText && !pinnedAtLargeText
                VStack(spacing: 0) {
                    if showsHero {
                        AuthHeroBand(band: band)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.medium) {
                            content
                            if actionsInline, hasActions {
                                actionStack
                            }
                        }
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.vertical, Spacing.large)
                        .frame(maxWidth: ControlSize.sheetMaxWidth, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .scrollBounceBehavior(.basedOnSize)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if !actionsInline, hasActions {
                            actionStack
                                .padding(.horizontal, Spacing.gutter)
                                .padding(.top, Spacing.mediumSmall)
                                .padding(.bottom, Spacing.medium)
                                .frame(maxWidth: ControlSize.sheetMaxWidth)
                                .frame(maxWidth: .infinity)
                                .background(Palette.background)
                        }
                    }
                }
                .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: band)
            }
            .background(Palette.background)
        }

        private var hasActions: Bool { Actions.self != EmptyView.self }

        private var actionStack: some View {
            VStack(spacing: Spacing.extraSmall) {
                actions
            }
        }
    }

    extension AuthScaffold where Actions == EmptyView {
        init(compactHero: Bool = false, @ViewBuilder content: () -> Content) {
            self.init(compactHero: compactHero, content: content, actions: { EmptyView() })
        }
    }

    /// The compact hero: the lockup on the plum with the sign-in trails, ending in the sheet's
    /// curve. A slim band at large text, on a short window or with the keyboard up.
    private struct AuthHeroBand: View {
        let band: Bool

        var body: some View {
            HeroSection(trail: .signIn, compact: band) {
                EmptyView()
            } content: {
                WaiveraLogo(style: .lockup, ink: HeroPalette.onHeader)
                    .frame(height: CGFloat(HeroMetrics.lockupCompact))
                    .frame(maxWidth: .infinity)
                    .frame(height: CGFloat(band ? HeroMetrics.barHeight : HeroMetrics.gateHeaderHeight))
            }
        }
    }

    /// Icon tile, heading and supporting text at the top of a gate screen (Android `AuthHeader`).
    /// `welcome` is for a screen that invites rather than reports (finishing signup, the primer):
    /// the header sits on a plain card, as the wash is for celebrations only. Errors, offline and
    /// password screens stay plain and calm.
    struct AuthHeader: View {
        let systemImage: String
        let title: String
        let message: String
        var tone: TileTone = .brand
        var welcome = false

        var body: some View {
            if welcome {
                SurfaceCard { stack }
            } else {
                stack
            }
        }

        private var stack: some View {
            VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                IconTile(
                    systemImage: systemImage,
                    tone: tone,
                    size: ControlSize.stateIconTile,
                    glyphSize: ControlSize.stateIconGlyph
                )
                Text(title)
                    .waiveraTextStyle(.headlineSmall)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .waiveraTextStyle(.bodyLarge)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Supporting copy under a gate's header.
    struct AuthHelp: View {
        let text: String

        var body: some View {
            Text(text)
                .waiveraTextStyle(.bodyMedium)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A gate's primary action and Sign out under it (Android `GateActions`). The busy primary
    /// keeps its size and says what is happening; Sign out waits until it finishes.
    struct GateActions: View {
        let title: String
        let busyTitle: String
        let isBusy: Bool
        var isEnabled = true
        let onPrimary: () -> Void
        let onSignOut: (() -> Void)?
        var identifier = "state.action"

        var body: some View {
            WaiveraButton(title, isLoading: isBusy, loadingTitle: busyTitle, action: onPrimary)
                .disabled(!isEnabled && !isBusy)
                .accessibilityIdentifier(identifier)
            if let onSignOut {
                GateSignOut(isEnabled: !isBusy, action: onSignOut)
            }
        }
    }

    /// The quiet Sign out on every gate.
    struct GateSignOut: View {
        let isEnabled: Bool
        let action: () -> Void

        var body: some View {
            WaiveraButton(AuthStrings.signOut, variant: .text, fillsWidth: true, action: action)
                .disabled(!isEnabled)
        }
    }

    extension View {
        /// Rejected credentials: the one auth outcome that vibrates (the form also shakes once,
        /// `rejectShake`). Every other failure and every success is silent; its message is enough.
        func signInRejectedFeedback(rejections: Int) -> some View {
            waiveraHaptic(.signInRejected, trigger: rejections) { old, new in new > old }
        }

        /// A banner opening downward from its top and fading in, an even push of what is below
        /// (Android `AuthAnimatedVisibility`); a fade under Reduce Motion.
        func authNoticeTransition() -> some View {
            modifier(NoticeTransition())
        }
    }

    private struct NoticeTransition: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        func body(content: Content) -> some View {
            content.transition(Motion.transition(edge: .top, reduceMotion: reduceMotion))
        }
    }
#endif

#if canImport(UIKit) && DEBUG
    import SwiftUI

    /// Renders `content` once an async fixture is ready, so previews show the same prepared
    /// states as the snapshot tests.
    struct FixturePreview<Model, Content: View>: View {
        private let make: @MainActor () async -> Model
        private let content: (Model) -> Content
        @State private var model: Model?

        init(
            _ make: @escaping @MainActor () async -> Model,
            @ViewBuilder content: @escaping (Model) -> Content
        ) {
            self.make = make
            self.content = content
        }

        var body: some View {
            Group {
                if let model {
                    content(model)
                } else {
                    Color.clear
                }
            }
            .task { model = await make() }
        }
    }
#endif
