import SwiftUI
import WaiveraDesign
import WaiveraRouting

/// The bottom tabs Today / Chat / Schedule (Android `WaiveraNavigationBar`): the bar's own fill
/// under a top hairline, and one solid violet pill behind the selected tab's white glyph. The
/// pill slides to the tab just picked on the press spring and that glyph pops; the label turns
/// heavier. Chat carries the unread count in the attention rose, ringed in the bar's colour.
///
/// The pill is decoration: the label, the selected trait and the count carry the meaning.
/// Under Reduce Motion the pill fades across instead of sliding and nothing pops. A tab switch
/// never vibrates. Labels stop growing at 150% and the count at 130%: the 24pt glyph does not
/// grow, so an uncapped count would swallow it.
struct WaiveraTabBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var pillSpace
    let selected: AppTab
    let unreadTotal: Int
    let onSelect: (AppTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                TabBarItem(
                    tab: tab,
                    isSelected: tab == selected,
                    unread: tab == .chat ? unreadTotal : 0,
                    pillSpace: pillSpace
                ) {
                    onSelect(tab)
                }
            }
        }
        // At the largest text the count sits beside the glyph's top edge, so the bar keeps
        // room above it.
        .padding(.top, dynamicTypeSize.isExtraLargeText ? Spacing.mediumSmall : Spacing.extraSmall)
        .padding(.bottom, Spacing.extraSmall)
        .frame(maxWidth: .infinity)
        .background(Palette.navBar.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Palette.navBarBorder)
                .frame(height: Spacing.hairline)
                .accessibilityHidden(true)
        }
        .animation(Motion.animation(reduceMotion ? .state : .press, reduceMotion: false), value: selected)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tabBar")
    }
}

private struct TabBarItem: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let tab: AppTab
    let isSelected: Bool
    let unread: Int
    let pillSpace: Namespace.ID
    let action: () -> Void
    /// Counts the times this tab was picked, so only the tab just picked pops.
    @State private var picks = 0

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xxSmall) {
                glyph
                Text(tab.title)
                    .waiveraTextStyle(.labelMedium)
                    .fontWeight(isSelected ? .heavy : .semibold)
                    .foregroundStyle(isSelected ? Palette.text : Palette.textSecondary)
                    .lineLimit(1)
                    .dynamicTypeSize(...TypeScale.cap(atScale: TypeScale.extraLargeScale).dynamicTypeSize)
            }
            .frame(maxWidth: .infinity, minHeight: ControlSize.minHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press(.compact))
        .onChange(of: isSelected) { _, nowSelected in
            if nowSelected { picks += 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tab.title))
        .accessibilityValue(Text(unread > 0 ? AppStrings.tabUnread(unread) : ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }

    private var glyph: some View {
        ZStack {
            if isSelected {
                pill
            }
            Image(systemName: tab.systemImage)
                .resizable()
                .scaledToFit()
                .symbolVariant(isSelected ? .fill : .none)
                .frame(width: ControlSize.icon, height: ControlSize.icon)
                .foregroundStyle(isSelected ? Palette.onAccent : Palette.textSecondary)
                .overlay(alignment: .topTrailing) {
                    TabBadge(count: unread, besideGlyph: dynamicTypeSize.isExtraLargeText)
                }
                .popOnChange(of: picks)
        }
        .frame(width: ControlSize.navIndicatorWidth, height: ControlSize.navIndicatorHeight)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var pill: some View {
        let shape = Capsule().fill(Palette.selectedFill)
        if reduceMotion {
            shape.transition(.opacity)
        } else {
            // One pill shared by every tab, so a switch moves it across instead of showing two.
            shape.matchedGeometryEffect(id: "tabPill", in: pillSpace)
        }
    }
}

/// The unread count on the glyph's top-trailing corner. Its leading edge stays put and a wider
/// count grows away from the glyph, so "99+" never covers the icon it labels. At the largest
/// text it moves clear of the glyph: leading on the glyph's trailing edge, centred on its top.
private struct TabBadge: View {
    let count: Int
    let besideGlyph: Bool

    var body: some View {
        PopVisibility(isVisible: BadgeFormatter.text(for: count) != nil) {
            let text = BadgeFormatter.text(for: count) ?? ""
            Text(verbatim: text)
                .waiveraTextStyle(.badge)
                .foregroundStyle(Palette.onAccent)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Spacing.extraSmall)
                .frame(minWidth: ControlSize.navBadgeMin, minHeight: ControlSize.navBadgeMin)
                .background(Palette.navBadge, in: Capsule())
                // Ringed in the bar's colour so it reads as cut out of the bar.
                .padding(ControlSize.navBadgeRing)
                .background(Palette.navBar, in: Capsule())
                .popOnChange(of: text)
                .dynamicTypeSize(...TypeScale.cap(atScale: TypeScale.ringMaxScale).dynamicTypeSize)
        }
        .fixedSize()
        .alignmentGuide(.trailing) { dimensions in
            dimensions[.leading] + (besideGlyph ? 0 : Spacing.small)
        }
        .alignmentGuide(.top) { dimensions in
            besideGlyph ? dimensions[VerticalAlignment.center] : dimensions[.bottom] - Spacing.small
        }
        .allowsHitTesting(false)
    }
}

#if DEBUG
    private struct TabBarPreview: View {
        @State private var selected = AppTab.chat
        @State private var unread = 4

        var body: some View {
            VStack {
                Spacer()
                Button("Add unread") { unread += 48 }
                WaiveraTabBar(selected: selected, unreadTotal: unread) { selected = $0 }
            }
            .background(Palette.background)
        }
    }

    #Preview("Light") { TabBarPreview() }
    #Preview("Dark") { TabBarPreview().preferredColorScheme(.dark) }
    #Preview("AX5") { TabBarPreview().dynamicTypeSize(.accessibility5) }
#endif
