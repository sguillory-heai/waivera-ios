import Foundation

/// The public Terms of Service and Privacy Policy pages on the web app, linked from sign-in.
/// They hang off the configured web base (`WaiveraWebBaseURL`, per `.xcconfig`), at the routes the
/// web Login page links, so no environment is ever written here.
public struct LegalLinks: Equatable, Sendable {
    /// Web app routes (`sprout_web` App.tsx; linked from its Login page).
    public static let termsOfServicePath = "terms-of-service"
    public static let privacyPolicyPath = "privacy-policy"

    public let termsOfService: URL
    public let privacyPolicy: URL

    public init(termsOfService: URL, privacyPolicy: URL) {
        self.termsOfService = termsOfService
        self.privacyPolicy = privacyPolicy
    }

    /// `nil` when the build has no web base or it is not an http(s) address, so the screen shows
    /// no dead links. Pages resolve against the base as a browser would (Android's
    /// `HttpUrl.resolve`): a base ending in "/" keeps its path, otherwise its last segment is
    /// replaced.
    public static func from(webBase: URL?) -> LegalLinks? {
        guard let webBase, let scheme = webBase.scheme?.lowercased(), scheme == "https" || scheme == "http",
            webBase.host?.isEmpty == false
        else { return nil }
        guard let terms = resolve(termsOfServicePath, against: webBase),
            let privacy = resolve(privacyPolicyPath, against: webBase)
        else { return nil }
        return LegalLinks(termsOfService: terms, privacyPolicy: privacy)
    }

    private static func resolve(_ path: String, against base: URL) -> URL? {
        // An empty base path is "/" (RFC 3986 §5.2.3), so "https://host" gives "https://host/path".
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        if components?.path.isEmpty == true { components?.path = "/" }
        guard let normalized = components?.url else { return nil }
        return URL(string: path, relativeTo: normalized)?.absoluteURL
    }
}
