import ChatFeature
import SwiftUI
import WaiveraDesign
import WaiveraRouting

/// Bottom tabs Today / Chat / Schedule, one `NavigationStack` per tab bound to the router.
///
/// The tabs keep the system `TabView` for its per-tab state, but its bar is hidden and the
/// shell draws `WaiveraTabBar` (the sliding pill and the icon pop, Android
/// `WaiveraNavigationBar`). As on Android the bar shows on tab roots only: a pushed screen gets
/// the full height and the bar slides away under it.
struct MainTabView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView(selection: selection) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                TabStack(model: model, tab: tab)
                    .tag(tab)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsTabBar {
                WaiveraTabBar(
                    selected: model.navigation.selectedTab,
                    unreadTotal: model.unreadTotal,
                    onSelect: { model.select($0) }
                )
                .transition(Motion.transition(edge: .bottom, reduceMotion: reduceMotion))
            }
        }
        .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: showsTabBar)
        .environment(\.waiveraAccountMenu, accountMenu)
        .modifier(ShellBanners(model: model))
        .sheet(item: sheet) { presented in
            switch presented {
            case .newChat:
                NavigationStack {
                    NewChatView(
                        onOpenConversation: { model.openConversationFromSheet($0) },
                        onDismiss: { model.dismissSheet() }
                    )
                }
            }
        }
        .sheet(isPresented: $model.isAccountMenuPresented) {
            AccountMenuSheet(accountName: model.userDisplayName) { model.openFromAccountMenu($0) }
                .waiveraSheetPresentation()
        }
    }

    /// Tab roots only, as on Android.
    private var showsTabBar: Bool {
        model.navigation.path(for: model.navigation.selectedTab).isEmpty
    }

    private var accountMenu: AccountMenuEntry {
        AccountMenuEntry(name: model.userDisplayName) { model.presentAccountMenu() }
    }

    private var selection: Binding<AppTab> {
        Binding(get: { model.navigation.selectedTab }, set: { model.select($0) })
    }

    private var sheet: Binding<AppSheet?> {
        Binding(get: { model.navigation.sheet }, set: { model.navigation.sheet = $0 })
    }
}

private struct TabStack: View {
    @Bindable var model: AppModel
    let tab: AppTab

    var body: some View {
        NavigationStack(path: path) {
            TabRootView(model: model, tab: tab)
                .toolbar(.hidden, for: .tabBar)
                .navigationDestination(for: AppRoute.self) { route in
                    // Every screen hides the system bar; the shell draws its own on tab roots.
                    RouteDestinationView(model: model, route: route)
                        .toolbar(.hidden, for: .tabBar)
                }
        }
    }

    private var path: Binding<[AppRoute]> {
        Binding(get: { model.navigation.path(for: tab) }, set: { model.navigation.setPath($0, for: tab) })
    }
}

extension AppTab {
    var title: String {
        switch self {
        case .today: AppStrings.tabToday
        case .chat: AppStrings.tabChat
        case .schedule: AppStrings.tabSchedule
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .chat: "bubble.left.and.bubble.right"
        case .schedule: "calendar"
        }
    }
}
