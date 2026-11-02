#if canImport(UIKit)
    import SwiftUI

    /// An icon action in the top bar (a call, search). White on the plum, with an optional count.
    public struct TopBarAction: Identifiable {
        public let id: String
        public let systemImage: String
        public let accessibilityLabel: String
        public let badgeCount: Int
        public let action: () -> Void

        public init(
            id: String,
            systemImage: String,
            accessibilityLabel: String,
            badgeCount: Int = 0,
            action: @escaping () -> Void
        ) {
            self.id = id
            self.systemImage = systemImage
            self.accessibilityLabel = accessibilityLabel
            self.badgeCount = badgeCount
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
        private let onSubtitle: (() -> Void)?
        private let subtitleActionLabel: String?
        private let sheetColor: Color
        private let heroContent: HeroContent

        public init(
            title: String,
            subtitle: String? = nil,
            actions: [TopBarAction] = [],
            sheetColor: Color = Palette.background,
            onBack: (() -> Void)? = nil,
            onSubtitle: (() -> Void)? = nil,
            subtitleActionLabel: String? = nil,
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
            self.onSubtitle = onSubtitle
            self.subtitleActionLabel = subtitleActionLabel
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
                        Image(systemName: item.systemImage)
                            .font(.system(size: ControlSize.icon - Spacing.xxSmall, weight: .semibold))
                            .foregroundStyle(HeroPalette.onHeader)
                            .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                            .contentShape(Rectangle())
                            .overlay(alignment: .topTrailing) {
                                CountBadge(count: item.badgeCount)
                            }
                    }
                    .buttonStyle(.press(.compact))
                    .accessibilityLabel(Text(item.accessibilityLabel))
                    .accessibilityIdentifier("topBar.\(item.id)")
                }
            }
            .padding(.horizontal, Spacing.xxSmall)
            .frame(minHeight: CGFloat(HeroMetrics.barHeight))
        }

        @ViewBuilder private func subtitleView(_ subtitle: String) -> some View {
            let line = Text(subtitle)
                .waiveraTextStyle(.labelMedium)
                .foregroundStyle(HeroPalette.onHeaderSecondary)
                .lineLimit(2)
            if let onSubtitle {
                Button(action: onSubtitle) {
                    HStack(spacing: Spacing.xxSmall) {
                        line
                        Image(systemName: "chevron.right")
                            .font(.system(size: ControlSize.iconSmall - Spacing.xxSmall, weight: .semibold))
                            .foregroundStyle(HeroPalette.onHeaderSecondary)
                    }
                    .frame(minHeight: ControlSize.minHitTarget / 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.compact))
                .accessibilityHint(Text(subtitleActionLabel ?? ""))
                .accessibilityIdentifier("topBar.subtitle")
            } else {
                line.accessibilityIdentifier("topBar.subtitle")
            }
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
            onBack: (() -> Void)? = nil,
            onSubtitle: (() -> Void)? = nil,
            subtitleActionLabel: String? = nil
        ) {
            self.init(
                title: title,
                subtitle: subtitle,
                actions: actions,
                sheetColor: sheetColor,
                onBack: onBack,
                onSubtitle: onSubtitle,
                subtitleActionLabel: subtitleActionLabel
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
            sheetColor: Color = Palette.background,
            onSubtitle: (() -> Void)? = nil,
            subtitleActionLabel: String? = nil
        ) -> some View {
            waiveraTopBar {
                WaiveraTopBar(
                    title: title,
                    subtitle: subtitle,
                    actions: actions,
                    sheetColor: sheetColor,
                    onSubtitle: onSubtitle,
                    subtitleActionLabel: subtitleActionLabel
                )
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
