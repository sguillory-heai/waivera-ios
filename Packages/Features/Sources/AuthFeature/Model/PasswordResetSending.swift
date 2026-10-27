import Foundation
import WaiveraData

/// Sends Firebase's password-reset email (`accounts:sendOobCode`, `requestType: PASSWORD_RESET`).
///
/// Local adapter for a data-layer gap: `SessionRepository` has no reset call yet
/// (docs/requests/auth-feature.md, request 1). Until it does, nothing conforms and the sign-in
/// screen hides "Forgot password?"; tests and previews pass a fake.
public protocol PasswordResetSending: Sendable {
    /// Throws a `WaiveraError`. An unknown address must not be reported differently from a sent
    /// link, so the screen treats `.auth(.invalidCredentials)` and `.notFound` as sent.
    func sendPasswordReset(email: String) async throws
}

enum PasswordResetAdapter {
    /// The reset sender for this session, once the data layer offers one.
    static func sender(for session: (any SessionRepository)?) -> (any PasswordResetSending)? {
        session as? any PasswordResetSending
    }
}
