#if canImport(UIKit)
    import SwiftUI

    /// An icon action in the top bar (a call, search). White on the plum, with an optional count.
    public struct TopBarAction: Identifiable {
        public let id: String
        public let systemImage: String
        public let accessibilityLabel: String
        public let badgeCount: Int
        /// Dimmed and not tappable (a call before the chat has loaded).
        public let isEnabled: Bool
        /// A white spinner in place of the glyph while the action runs (a call opening).
        public let isBusy: Bool
        public let action: () -> Void

        public init(
            id: String,
            systemImage: String,
            accessibilityLabel: String,
            badgeCount: Int = 0,
            isEnabled: Bool = true,
            isBusy: Bool = false,
            action: @escaping () -> Void
        ) {
            self.id = id
            self.systemImage = systemImage
            self.accessibilityLabel = accessibilityLabel
            self.badgeCount = badgeCount
            self.isEnabled = isEnabled
            self.isBusy = isBusy
            self.action = action
        }
    }

    /// The screen top bar of every pushed screen (Android `WaiveraTopBar`): the plum hero behind
    /// the status bar, a back arrow, the title on the left in white (two lines at most) with an
    /// optional subtitle, icon actions on the right, and the first band of the rounded sheet the
    /// screen sits on. `heroContent` goes on the plum under the bar row (a person's avatar and
    /// name). Put it on a screen with `waiveraTopBar(...)`, which also hides the system bar.
    public struct WaiveraTopBar<HeroContent: View>: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        private var title: AnyView
        private let subtitle: String?
        private let actions: [TopBarAction]
        private let onBack: (() -> Void)?
        private let sheetColor: Color
        private let heroContent: HeroContent

        public init(
            title: String,
            subtitle: String? = nil,
            actions: [TopBarAction] = [],
            sheetColor: Color = Palette.background,
            onBack: (() -> Void)? = nil,
            @ViewBuilder heroContent: () -> HeroContent
        ) {
            self.title = AnyView(
                Text(title)
                    .waiveraTextStyle(.headlineSmall)
                    .foregroundStyle(HeroPalette.onHeader)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("topBar.title")
            )
            self.subtitle = subtitle
            self.actions = actions
            self.sheetColor = sheetColor
            self.onBack = onBack
            self.heroContent = heroContent()
        }

        public var body: some View {
            HeroSection(compact: dynamicTypeSize.isLargeText, sheetColor: sheetColor) {
                barRow
            } content: {
                heroContent
            }
        }

        private var barRow: some View {
            HStack(spacing: 0) {
                Button {
                    if let onBack { onBack() } else { dismiss() }
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: ControlSize.icon - Spacing.xxSmall, weight: .semibold))
                        .foregroundStyle(HeroPalette.onHeader)
                        .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press(.compact))
                .accessibilityLabel(Text(DesignStrings.goBack))
                .accessibilityIdentifier("topBar.back")
                VStack(alignment: .leading, spacing: 0) {
                    title
                    if let subtitle {
                        subtitleView(subtitle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Spacing.small)
                .padding(.leading, Spacing.xxSmall)
                ForEach(actions) { item in
                    Button(action: item.action) {
                        Group {
                            if item.isBusy {
                                ProgressView().tint(HeroPalette.onHeader)
                            } else {
                                Image(systemName: item.systemImage)
                                    .font(.system(size: ControlSize.icon - Spacing.xxSmall, weight: .semibold))
                                    .foregroundStyle(HeroPalette.onHeader)
                            }
                        }
                        .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                        .contentShape(Rectangle())
                        .overlay(alignment: .topTrailing) {
                            CountBadge(count: item.badgeCount)
                        }
                    }
                    .buttonStyle(.press(.compact))
                    .disabled(!item.isEnabled || item.isBusy)
                    .opacity(item.isEnabled ? 1 : Emphasis.disabled)
                    .accessibilityLabel(Text(item.accessibilityLabel))
                    .accessibilityIdentifier("topBar.\(item.id)")
                }
            }
            .padding(.horizontal, Spacing.xxSmall)
            .frame(minHeight: CGFloat(HeroMetrics.barHeight))
        }

        private func subtitleView(_ subtitle: String) -> some View {
            Text(subtitle)
                .waiveraTextStyle(.labelMedium)
                .foregroundStyle(HeroPalette.onHeaderSecondary)
                .lineLimit(2)
                .accessibilityIdentifier("topBar.subtitle")
        }
    }

    public extension WaiveraTopBar where HeroContent == EmptyView {
        /// A bar whose title the screen draws itself (a chat's name that shortens, with its
        /// members button under it), in the hero inks and left aligned.
        init(
            actions: [TopBarAction] = [],
            sheetColor: Color = Palette.background,
            onBack: (() -> Void)? = nil,
            @ViewBuilder titleView: () -> some View
        ) {
            self.init(title: "", actions: actions, sheetColor: sheetColor, onBack: onBack) { EmptyView() }
            title = AnyView(titleView())
        }

        init(
            title: String,
            subtitle: String? = nil,
            actions: [TopBarAction] = [],
            sheetColor: Color = Palette.background,
            onBack: (() -> Void)? = nil
        ) {
            self.init(
                title: title,
                subtitle: subtitle,
                actions: actions,
                sheetColor: sheetColor,
                onBack: onBack
            ) { EmptyView() }
        }
    }

    public extension View {
        /// Puts Android's plum top bar on a pushed screen and hides the system navigation bar.
        /// The edge swipe still goes back (`SwipeBack`). The screen keeps its own background.
        func waiveraTopBar(
            _ title: String,
            subtitle: String? = nil,
            actions: [TopBarAction] = [],
            sheetColor: Color = Palette.background
        ) -> some View {
            waiveraTopBar {
                WaiveraTopBar(title: title, subtitle: subtitle, actions: actions, sheetColor: sheetColor)
            }
        }

        /// The same, for a bar built by the screen (one with hero content).
        func waiveraTopBar(@ViewBuilder _ bar: () -> some View) -> some View {
            let bar = bar()
            return safeAreaInset(edge: .top, spacing: 0) { bar }
                .toolbar(.hidden, for: .navigationBar)
                .swipeBackEnabled()
        }
    }

    public extension View {
        /// For a scroll view whose hero scrolls away (Today, Schedule, Profile, Person): once the
        /// page has scrolled, the plum fills the status bar again. The status bar is light
        /// app-wide (project.yml), so without it the clock would sit white on page-coloured cards.
        /// At rest the hero itself shows there, glows included. iOS 17 cannot read the scroll
        /// offset, so there the band always shows.
        func plumStatusBarWhenScrolled() -> some View {
            modifier(PlumStatusBarWhenScrolled())
        }
    }

    private struct PlumStatusBarWhenScrolled: ViewModifier {
        @State private var isScrolled = false

        func body(content: Content) -> some View {
            tracked(content)
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .background(alignment: .bottom) {
                            HeroPalette.headerTop
                                .ignoresSafeArea(edges: .top)
                                .opacity(showsBand ? 1 : 0)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }

        private var showsBand: Bool {
            if #available(iOS 18, *) { return isScrolled }
            return true
        }

        @ViewBuilder private func tracked(_ content: Content) -> some View {
            if #available(iOS 18, *) {
                content.onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > Spacing.hairline
                } action: { _, scrolled in
                    isScrolled = scrolled
                }
            } else {
                content
            }
        }
    }

    /// The small count on a top bar action (white on rose, ringed in the plum).
    private struct CountBadge: View {
        let count: Int

        var body: some View {
            PopVisibility(isVisible: BadgeFormatter.text(for: count) != nil) {
                Text(verbatim: BadgeFormatter.text(for: count) ?? "")
                    .waiveraTextStyle(.badge)
                    .foregroundStyle(Palette.onAccent)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, Spacing.extraSmall)
                    .frame(minWidth: ControlSize.navBadgeMin, minHeight: ControlSize.navBadgeMin)
                    .background(Palette.navBadge, in: Capsule())
            }
            .accessibilityHidden(true)
        }
    }

    private struct TopBarGallery: View {
        var body: some View {
            NavigationStack {
                ScrollView {
                    Text(verbatim: "Content").padding(Spacing.medium)
                }
                .background(Palette.background)
                .waiveraTopBar(
                    "North team check-in with a much longer conversation title",
                    subtitle: "6 members",
                    actions: [TopBarAction(id: "call", systemImage: "video", accessibilityLabel: "Call") {}]
                )
            }
        }
    }

    #Preview("Light") { TopBarGallery() }
    #Preview("Dark") { TopBarGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { TopBarGallery().dynamicTypeSize(.accessibility5) }
#endif
