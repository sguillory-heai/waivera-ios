# 0004: Today-first tabs, typed routes and a Foundation routing package

Status: Accepted (2026-10-27)

## Context

The Expo app has five tabs (Chats, Activity, Calendar, Bookmarks, Profile), pushes that only ever
open a chat, and navigation rules spread across screens. The UX research recommends opening to a
Today view and keeping secondary destinations one tap away. AGENTS.md asks for a deep link for
every push target, and the routing rules (which tab, what the back button does, when a push is
shown in the foreground) are easy to get wrong without tests.

## Decision

- Three tabs: **Today, Chat, Schedule** (Tasks joins in phase 4). Activity folds into Today.
  Profile, People, Bookmarks and Settings open from the avatar in the Today and Chat top bars
  and push onto the selected tab.
- Every screen is a typed `AppRoute`. `waivera://` links, push payloads and the DEBUG
  `-WaiveraRoute` launch argument all resolve to a `Destination`, applied by one value-type
  reducer, `NavigationState`. External opens replace the target tab's stack (a push-opened chat
  backs out to the inbox); in-app navigation pushes.
- Routing lives in `Packages/WaiveraRouting` and push handling in `Packages/WaiveraNotifications`,
  both Foundation only so their rules are unit tested on Linux. UserNotifications and Firebase
  Messaging stay in an iOS-only target and the app target, behind protocols.
- Feature packages expose entry views that take navigation closures; only the app router imports
  more than one feature.

## Consequences

- Adding a screen means adding an `AppRoute` case, a `RouteCatalog` entry (so the screenshot tour
  covers it) and a case in `RouteDestinationView`; `docs/architecture/app-shell.md` lists them all.
- The Android app should use the same tab order, route names and `waivera://` grammar.
- The decision is reversible: the tab set is one enum and one view.
