/// How a navigation request reached the router. External opens replace the target tab's stack
/// so a push-opened chat backs out to the inbox (09-push §7); in-app opens push.
public enum NavigationOrigin: Sendable {
    case inApp
    case external
}

/// The whole navigation state of the signed-in shell, as a value, so the rules are testable.
public struct NavigationState: Equatable, Sendable {
    public var selectedTab: AppTab
    public private(set) var paths: [AppTab: [AppRoute]]
    public var sheet: AppSheet?

    public init(selectedTab: AppTab = .today) {
        self.selectedTab = selectedTab
        paths = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, []) })
        sheet = nil
    }

    public func path(for tab: AppTab) -> [AppRoute] {
        paths[tab] ?? []
    }

    public mutating func setPath(_ path: [AppRoute], for tab: AppTab) {
        paths[tab] = path
    }

    /// The top screen of the selected tab.
    public var visibleRoute: AppRoute? {
        path(for: selectedTab).last
    }

    /// The conversation on top of the selected tab, if any. Foreground push suppression does
    /// not read this: the data layer's presence (`ChatAlertsRepository`) owns that rule.
    public var visibleConversationID: Int? {
        guard sheet == nil else { return nil }
        return visibleRoute?.conversationID
    }

    /// Pushes a route on the selected tab (feature navigation closures).
    public mutating func push(_ route: AppRoute) {
        guard path(for: selectedTab).last != route else { return }
        paths[selectedTab, default: []].append(route)
    }

    public mutating func pop() {
        guard !path(for: selectedTab).isEmpty else { return }
        paths[selectedTab]?.removeLast()
    }

    /// Selecting the tab that is already selected returns it to its root.
    public mutating func select(_ tab: AppTab) {
        if tab == selectedTab {
            paths[tab] = []
        } else {
            selectedTab = tab
        }
    }

    /// Applies a deep link, push tap or launch route. Returns `false` when nothing changed,
    /// e.g. the push targets the conversation already on screen. "On screen" is the top of the
    /// selected tab whichever tab the destination belongs to, so a conversation open from Today
    /// is not stacked a second time on Chat (IF-12, as on Android). A new message highlight on
    /// the conversation already on top replaces the top entry in place.
    @discardableResult
    public mutating func open(_ destination: Destination, origin: NavigationOrigin = .external) -> Bool {
        let tab = destination.tab ?? selectedTab
        if destination.sheet == nil, sheet == nil, let target = destination.path.last {
            switch match(target, onTopOf: selectedTab) {
            case .same:
                return false
            case .newHighlight:
                var current = path(for: selectedTab)
                current[current.count - 1] = target
                paths[selectedTab] = current
                return true
            case .different:
                break
            }
        } else if destination.sheet == nil, sheet == nil, tab == selectedTab, path(for: tab).isEmpty {
            return false
        }
        selectedTab = tab
        switch origin {
        case .external:
            paths[tab] = destination.path
        case .inApp:
            for route in destination.path where paths[tab]?.last != route {
                paths[tab, default: []].append(route)
            }
        }
        sheet = destination.sheet
        return true
    }

    private enum TopMatch {
        case same
        case newHighlight
        case different
    }

    private func match(_ target: AppRoute, onTopOf tab: AppTab) -> TopMatch {
        guard let top = path(for: tab).last else { return .different }
        if top == target { return .same }
        // Same conversation or thread already open: never stack a duplicate (09-push §10).
        switch (target, top) {
        case (.conversation(let wanted, let highlight), .conversation(let shown, _)) where wanted == shown:
            return highlight == nil ? .same : .newHighlight
        case (.thread(let wanted, _, let highlight), .thread(let shown, _, _)) where wanted == shown:
            return highlight == nil ? .same : .newHighlight
        default:
            return .different
        }
    }
}
