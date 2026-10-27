/// Supplies the signed-in user's Firebase ID token.
public protocol AuthTokenProvider: Sendable {
    /// The current token, or a refreshed one when `forceRefresh` is true; `nil` when signed out.
    func idToken(forceRefresh: Bool) async throws -> String?
}
