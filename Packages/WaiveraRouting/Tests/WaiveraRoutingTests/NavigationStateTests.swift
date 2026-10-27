import Testing

@testable import WaiveraRouting

struct NavigationStateTests {
    @Test func startsOnTodayWithEmptyStacks() {
        let state = NavigationState()
        #expect(state.selectedTab == .today)
        #expect(AppTab.allCases.allSatisfy { state.path(for: $0).isEmpty })
        #expect(AppTab.allCases == [.today, .chat, .schedule])
    }

    @Test func pushOpenedChatBacksOutToTheInbox() {
        var state = NavigationState()
        state.push(.profile)
        let changed = state.open(.conversation(42))
        #expect(changed)
        #expect(state.selectedTab == .chat)
        #expect(state.path(for: .chat) == [.conversation(conversationID: 42, targetMessageID: nil)])
        // Today keeps its own stack.
        #expect(state.path(for: .today) == [.profile])
    }

    @Test func pushForAnotherChatReplacesTheOpenChat() {
        var state = NavigationState()
        state.open(.conversation(7))
        state.open(.conversation(42))
        #expect(state.path(for: .chat) == [.conversation(conversationID: 42, targetMessageID: nil)])
        state.pop()
        #expect(state.path(for: .chat).isEmpty)
    }

    @Test func pushForTheVisibleChatDoesNothing() {
        var state = NavigationState()
        state.open(.conversation(42))
        let changed = state.open(.conversation(42, targetMessageID: 9312))
        #expect(!changed)
        #expect(state.path(for: .chat) == [.conversation(conversationID: 42, targetMessageID: nil)])
    }

    @Test func sameChatOnAnotherTabIsNotTreatedAsVisible() {
        var state = NavigationState()
        state.open(.conversation(42))
        state.select(.today)
        let changed = state.open(.conversation(42))
        #expect(changed)
        #expect(state.selectedTab == .chat)
    }

    @Test func visibleConversationFollowsTheSelectedTabTop() {
        var state = NavigationState()
        #expect(state.visibleConversationID == nil)
        state.open(.conversation(7))
        #expect(state.visibleConversationID == 7)
        state.push(.thread(rootMessageID: 9330, conversationID: 7, targetMessageID: nil))
        #expect(state.visibleConversationID == 7)
        state.select(.schedule)
        #expect(state.visibleConversationID == nil)
        state.select(.chat)
        state.sheet = .newChat
        #expect(state.visibleConversationID == nil)
    }

    @Test func inAppOpenPushesOntoTheCurrentStack() {
        var state = NavigationState()
        state.push(.activity)
        state.open(Destination(tab: nil, path: [.settings]), origin: .inApp)
        #expect(state.path(for: .today) == [.activity, .settings])
    }

    @Test func externalAvatarDestinationReplacesTheCurrentStack() {
        var state = NavigationState(selectedTab: .schedule)
        state.push(.calendarEvent(eventID: "evt_1"))
        state.open(Destination(tab: nil, path: [.settings, .notificationSettings]))
        #expect(state.selectedTab == .schedule)
        #expect(state.path(for: .schedule) == [.settings, .notificationSettings])
    }

    @Test func pushingTheSameRouteTwiceDoesNotStack() {
        var state = NavigationState()
        state.push(.bookmarks)
        state.push(.bookmarks)
        #expect(state.path(for: .today) == [.bookmarks])
    }

    @Test func reselectingATabPopsToRoot() {
        var state = NavigationState()
        state.open(.conversation(7))
        state.select(.chat)
        #expect(state.path(for: .chat).isEmpty)
    }

    @Test func openingARootWhenAlreadyThereIsANoOp() {
        var state = NavigationState(selectedTab: .chat)
        let changed = state.open(.inbox)
        #expect(!changed)
    }

    @Test func sheetDestinationPresentsOverTheTab() {
        var state = NavigationState()
        state.open(Destination(tab: .chat, sheet: .newChat))
        #expect(state.selectedTab == .chat)
        #expect(state.sheet == .newChat)
        state.open(.conversation(7))
        #expect(state.sheet == nil)
    }
}

struct RouteCatalogTests {
    @Test func everyLinkEntryParses() {
        for entry in RouteCatalog.links {
            #expect(entry.destination != nil, "\(entry.name) does not parse")
        }
    }

    @Test func namesAreUniqueAndFileSafe() {
        let names = RouteCatalog.all.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { $0.allSatisfy { $0.isLetter || $0 == "-" } })
    }

    @Test func everyRouteCaseHasACatalogEntry() {
        let routes = RouteCatalog.links.compactMap(\.destination).flatMap(\.path)
        let covered = Set(routes.map(caseName))
        let expected: Set<String> = [
            "activity", "conversation", "thread", "calendarEvent", "profile", "organization", "people", "person",
            "bookmarks", "settings", "notificationSettings", "appearanceSettings", "accountSettings",
            "changePassword",
        ]
        #expect(covered == expected)
        #expect(RouteCatalog.gates.count == GateScreen.allCases.count)
    }

    @Test func everyStateVariantOpensItsRouteUnderAScenario() {
        #expect(RouteCatalog.states.count == RouteCatalog.stateRoutes.count * RouteCatalog.stateScenarios.count)
        for entry in RouteCatalog.states {
            guard let scenario = entry.scenario else {
                Issue.record("\(entry.name) has no scenario")
                continue
            }
            #expect(RouteCatalog.stateScenarios.contains(scenario))
            let base = String(entry.name.dropLast(scenario.count + 1))
            #expect(RouteCatalog.entry(named: base)?.target == entry.target, "\(entry.name)")
            #expect(entry.destination != nil)
        }
        #expect(RouteCatalog.entry(named: "today-empty")?.scenario == "empty")
        #expect(RouteCatalog.entry(named: "calendar-event-failing")?.target == .link("waivera://calendar/evt_8f2b19c4"))
        #expect(RouteCatalog.links.allSatisfy { $0.scenario == nil })
    }

    @Test func botConversationAndEventScreensAreInTheTour() {
        #expect(RouteCatalog.entry(named: "conversation-bot")?.destination == .conversation(90))
        #expect(RouteCatalog.entry(named: "calendar-event-invite")?.destination == .calendarEvent("evt_demo_invite"))
        #expect(RouteCatalog.entry(named: "calendar-event-checkin")?.destination == .calendarEvent("evt_demo_checkin"))
    }

    @Test func everyGateHasAStableLaunchName() {
        #expect(
            RouteCatalog.gates.map(\.name) == [
                "loading", "sign-in", "bootstrap-failed", "configuration-missing", "password-change",
                "onboarding-required", "notification-primer",
            ]
        )
        #expect(RouteCatalog.entry(named: "bootstrap-failed")?.target == .gate(.bootstrapFailed))
    }

    private func caseName(_ route: AppRoute) -> String {
        String(String(describing: route).prefix { $0 != "(" })
    }
}
