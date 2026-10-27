import Foundation

/// What the app does with a URL any screen asks to open (AS-04). The app installs it as the
/// SwiftUI `openURL` action at the root, so a link that skipped a screen's own check (a rich
/// text link, a server value) still cannot launch another app's scheme.
public enum LinkPolicy {
    public enum Decision: Equatable, Sendable {
        /// One of the app's own `waivera://` links: navigate, never leave the app.
        case navigate(Destination)
        /// An `http` or `https` link with a host: the system opens it in the browser.
        case browser(URL)
        /// Anything else (`tel:`, `file:`, other apps' schemes, an unknown `waivera://` path).
        case blocked
    }

    public static func decide(_ url: URL) -> Decision {
        let scheme = url.scheme?.lowercased()
        if scheme == DeepLink.scheme {
            return DeepLink.destination(from: url).map(Decision.navigate) ?? .blocked
        }
        guard scheme == "http" || scheme == "https", let host = url.host,
            !host.trimmingCharacters(in: .whitespaces).isEmpty
        else { return .blocked }
        return .browser(url)
    }
}
