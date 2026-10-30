import Foundation

/// What the inbox header shows, as pure rules (Android `ChatListHeaderRulesTest`). One connection
/// signal at a time: the shell's banner owns offline and reconnecting, a healthy connection shows
/// nothing, and the quiet "Connecting" pill appears only when start-up is slow and nothing else
/// is saying something.
enum ChatListHeaderRules {
    /// How long a start-up may stay "Connecting" before the pill appears.
    static let connectingPillDelay: Duration = .seconds(2)

    /// "Online" is the normal state and is not news; only a start-up still connecting gets the pill.
    static func showsConnectingPill(_ state: ChatListState) -> Bool {
        guard state.connection == .connecting, state.refreshError == nil else { return false }
        if case .error = state.content { return false }
        return true
    }

    /// "Couldn't refresh your chats" while saved rows show; folded into the shell's banner while
    /// the connection is down, and never under a full-screen error.
    static func showsRefreshBanner(_ state: ChatListState) -> Bool {
        guard state.refreshError != nil else { return false }
        switch state.connection {
        case .offline, .reconnecting: return false
        case .online, .connecting: return true
        }
    }
}

/// Where a row sits on the inbox's one card (concept A's grouped list): the first row takes the
/// card's top corners, the last its bottom corners, so the rows read as one card on the page.
enum InboxCardPosition: Sendable, Hashable {
    case first, middle, last, single

    /// The last row has no divider under it.
    var isLast: Bool { self == .last || self == .single }
    var roundsTop: Bool { self == .first || self == .single }
    var roundsBottom: Bool { isLast }

    static func of(index: Int, count: Int) -> InboxCardPosition {
        if count <= 1 { return .single }
        if index == 0 { return .first }
        return index == count - 1 ? .last : .middle
    }
}
