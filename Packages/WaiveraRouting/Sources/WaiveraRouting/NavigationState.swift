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
    /// e.g. the push targets the conversation already on screen.
    @discardableResult
    public mutating func open(_ destination: Destination, origin: NavigationOrigin = .external) -> Bool {
        let tab = destination.tab ?? selectedTab
        if destination.sheet == nil, isAlreadyShowing(destination, on: tab) {
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

    private func isAlreadyShowing(_ destination: Destination, on tab: AppTab) -> Bool {
        guard tab == selectedTab, sheet == nil else { return false }
        let current = path(for: tab)
        guard let target = destination.path.last else { return current.isEmpty }
        guard let top = current.last else { return false }
        if top == target { return true }
        // Same conversation already open: do not stack a duplicate (09-push §10).
        if case .conversation(let wanted, _) = target, case .conversation(let shown, _) = top {
            return wanted == shown
        }
        if case .thread(let wanted, _, _) = target, case .thread(let shown, _, _) = top {
            return wanted == shown
        }
        return false
    }
}
