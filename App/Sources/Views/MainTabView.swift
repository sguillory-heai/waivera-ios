import ChatFeature
import SwiftUI
import WaiveraDesign
import WaiveraRouting

/// Bottom tabs Today / Chat / Schedule, one `NavigationStack` per tab bound to the router.
struct MainTabView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView(selection: selection) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                TabStack(model: model, tab: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .modifier(LiquidGlassTabBar())
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
                .navigationDestination(for: AppRoute.self) { route in
                    RouteDestinationView(model: model, route: route)
                }
        }
    }

    private var path: Binding<[AppRoute]> {
        Binding(get: { model.navigation.path(for: tab) }, set: { model.navigation.setPath($0, for: tab) })
    }
}

/// iOS 26 Liquid Glass: the tab bar already adopts glass when built with the iOS 26 SDK; this
/// adds the minimize-on-scroll behaviour. Older systems keep the standard tab bar.
private struct LiquidGlassTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
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
