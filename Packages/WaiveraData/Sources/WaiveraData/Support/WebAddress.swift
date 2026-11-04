import Foundation

/// Pages on the configured web app, for whatever the phone has no screen for. Only the web app's
/// own scheme, host and port are ever returned, so a server path can never send someone to
/// another site.
public enum WebAddress {
    /// `path` (site-relative, such as "/task/HEA-1042/files") on `base`; nil without a base or
    /// when the path resolves anywhere else.
    public static func page(_ path: String, on base: URL?) -> URL? {
        guard let base, let url = URL(string: path, relativeTo: base)?.absoluteURL,
            let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            scheme == base.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty,
            host == base.host?.lowercased(), url.port == base.port
        else { return nil }
        return url
    }
}
