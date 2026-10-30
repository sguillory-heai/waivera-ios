import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// Everything the sign-in screen shows, and the only code that submits credentials.
///
/// The session repository owns Firebase and the backend bootstrap. This model validates, submits
/// once, follows the session for the "Connecting to Waivera…" state and maps every failure to a
/// `WaiveraError` (never provider text). On success the app's gate moves on by itself, so there
/// is no navigation here.
@MainActor
@Observable
public final class SignInModel {
    public enum Phase: Equatable, Sendable {
        case idle
        /// Firebase sign-in in flight.
        case signingIn
        case sendingReset
    }

    /// The single notice above the form.
    public enum Notice: Equatable, Sendable {
        case failed(WaiveraError)
        /// A reset link was requested for this address (shown back to the person).
        case resetSent(email: String)
        /// A Terms of Service or Privacy Policy link found nothing that could open it. Calm, with
        /// no haptic: the person did nothing wrong and their typing is untouched.
        case linkUnavailable
    }

    public private(set) var email = ""
    /// Kept only while the form is on screen; cleared once a session exists.
    public private(set) var password = ""
    public private(set) var emailIssue: AuthFieldIssue?
    public private(set) var passwordIssue: AuthFieldIssue?
    public private(set) var phase: Phase = .idle
    public private(set) var notice: Notice?
    /// The backend bootstrap after a successful Firebase sign-in (01 §3 "bootstrapping").
    public private(set) var isConnecting = false
    /// `false` when the build has no server or Firebase settings; the form is then disabled.
    public private(set) var isConfigured: Bool
    /// Bumped on every failure.
    public private(set) var failureCount = 0
    /// Bumped when a reset link is sent.
    public private(set) var successCount = 0
    /// Bumped only when the credentials were rejected: the one sign-in moment that vibrates and
    /// shakes the form (haptics policy, 2026-10-29). Field errors, network and offline failures
    /// and reset failures show their message and nothing else.
    public private(set) var rejectionCount = 0

    @ObservationIgnored private var session: (any SessionRepository)?

    public init(session: (any SessionRepository)?) {
        self.session = session
        isConfigured = session != nil
        if let state = session?.currentState { apply(state) }
    }

    // MARK: Derived state

    /// "Forgot password?" needs a configured session (Firebase sends the email).
    public var canResetPassword: Bool { session != nil }
    public var fieldsEnabled: Bool { isConfigured && phase == .idle && !isConnecting }
    /// Both fields have something in them (01 §3). The button itself stays enabled while
    /// `fieldsEnabled`, so a tap with an empty field explains what is missing.
    public var canSubmit: Bool {
        fieldsEnabled && !AuthValidation.normalizedEmail(email).isEmpty && !password.isEmpty
    }

    /// Spinner on the sign-in button: Firebase or the backend bootstrap is running.
    public var isSigningIn: Bool { phase == .signingIn || isConnecting }

    // MARK: Session

    /// Follows the session until the calling task is cancelled (the view's `.task`).
    public func observeSession() async {
        guard let session else { return }
        for await state in session.states() {
            apply(state)
        }
    }

    func apply(_ state: SessionState) {
        isConnecting = state == .bootstrapping
        switch state {
        case .configurationMissing:
            isConfigured = false
            phase = .idle
        case .signedOut(let reason?):
            // A 401 at bootstrap signs out and says why (01 §2); a sign-out the person chose has
            // no reason and shows nothing.
            guard phase != .sendingReset else { return }
            phase = .idle
            if notice != .failed(reason) {
                notice = .failed(reason)
                password = ""
                failureCount += 1
            }
        case .bootstrapping, .bootstrapFailed:
            // Firebase accepted the credentials; the session owns what happens next.
            if phase == .signingIn { phase = .idle }
        case .signedIn, .passwordChangeRequired, .onboardingRequired:
            // This model can outlive the screen; on a shared device the next person to sign in
            // must start from an empty form.
            email = ""
            password = ""
            emailIssue = nil
            passwordIssue = nil
            notice = nil
            phase = .idle
        case .loading, .signedOut(nil):
            break
        }
    }

    // MARK: Editing

    public func setEmail(_ value: String) {
        guard value != email else { return }
        email = value
        emailIssue = nil
        if case .resetSent = notice { notice = nil }
        if case .failed = notice { notice = nil }
    }

    public func setPassword(_ value: String) {
        guard value != password else { return }
        password = value
        passwordIssue = nil
        if case .failed = notice { notice = nil }
    }

    public func dismissNotice() {
        notice = nil
    }

    /// Nothing on the device could open a legal page.
    public func linkUnavailable() {
        notice = .linkUnavailable
    }

    // MARK: Actions

    /// Return on the password field and the button both land here. The button stays enabled with
    /// empty fields, so a tap explains what is missing (field errors) instead of a dimmed button
    /// that says nothing (as on Android).
    public func submit() async {
        guard fieldsEnabled, let session else { return }
        let emailIssue = AuthValidation.emailIssue(email)
        let passwordIssue = AuthValidation.signInPasswordIssue(password)
        guard emailIssue == nil, passwordIssue == nil else {
            self.emailIssue = emailIssue
            self.passwordIssue = passwordIssue
            failureCount += 1
            return
        }
        phase = .signingIn
        notice = nil
        do {
            // Trimmed email, untouched password (01 §3).
            try await session.signIn(email: AuthValidation.normalizedEmail(email), password: password)
            // Stay busy until the session reports the bootstrap, so the button never flickers
            // back to "Sign in" between Firebase and the backend login. A signed-out state here
            // is the one from before this attempt.
            switch session.currentState {
            case .signedOut, .loading: break
            case let state: apply(state)
            }
        } catch {
            let mapped = WaiveraError.from(error)
            phase = .idle
            notice = .failed(mapped)
            failureCount += 1
            if mapped == .auth(.invalidCredentials) { rejectionCount += 1 }
        }
    }

    public func sendPasswordReset() async {
        guard fieldsEnabled, let session else { return }
        if let issue = AuthValidation.emailIssue(email) {
            emailIssue = issue
            failureCount += 1
            return
        }
        let address = AuthValidation.normalizedEmail(email)
        phase = .sendingReset
        notice = nil
        do {
            try await session.sendPasswordReset(email: address)
            resetSent(to: address)
        } catch {
            let mapped = WaiveraError.from(error)
            if Self.hidesAccountExistence(mapped) {
                // Never reveal whether an address has an account.
                resetSent(to: address)
            } else {
                phase = .idle
                notice = .failed(mapped)
                failureCount += 1
            }
        }
    }

    private func resetSent(to address: String) {
        phase = .idle
        notice = .resetSent(email: address)
        successCount += 1
    }

    private static func hidesAccountExistence(_ error: WaiveraError) -> Bool {
        error == .auth(.invalidCredentials) || error == .notFound
    }
}

extension SignInModel: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Never prints the email or password, even in a debug log, a crash report or `dump`.
    public nonisolated var description: String { "SignInModel(redacted)" }
    public nonisolated var debugDescription: String { description }
    public nonisolated var customMirror: Mirror { Mirror(self, children: [], displayStyle: .class) }
}
