import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// Firebase is signed in but the backend login failed for a reason other than 401/403 (01 §2).
/// Tells offline apart from a server failure, and shows Try again as busy until the session
/// answers, so a second tap cannot stack logins.
@MainActor
@Observable
public final class BootstrapFailedModel {
    public private(set) var error: WaiveraError?
    public private(set) var isRetrying = false
    public private(set) var failureCount = 0

    @ObservationIgnored private let session: (any SessionRepository)?
    @ObservationIgnored private let onRetry: () -> Void

    /// `onRetry` is the app's `retryBootstrap`; the model never calls the session to retry itself,
    /// so the gate owner stays the one place that starts a bootstrap.
    public init(session: (any SessionRepository)?, onRetry: @escaping () -> Void) {
        self.session = session
        self.onRetry = onRetry
        if let state = session?.currentState { apply(state) }
    }

    /// Network or timeout: the title says "offline" and the icon is the crossed-out wifi.
    public var isOffline: Bool { error == .offline }

    public func observeSession() async {
        guard let session else { return }
        for await state in session.states() {
            apply(state)
        }
    }

    func apply(_ state: SessionState) {
        switch state {
        case .bootstrapping:
            break
        case .bootstrapFailed(let newError):
            if isRetrying { failureCount += 1 }
            error = newError
            isRetrying = false
        default:
            isRetrying = false
        }
    }

    public func retry() {
        guard !isRetrying else { return }
        isRetrying = true
        onRetry()
    }
}

/// The account exists in Firebase but its Waivera setup is not finished. Nothing can be done
/// in the app (no onboarding contract exists, 01 §5), so the person can check again after
/// finishing setup elsewhere, or sign out.
@MainActor
@Observable
public final class OnboardingModel {
    public enum Status: Equatable, Sendable {
        case waiting
        case checking
        /// The check worked but the server still says setup is not finished.
        case stillPending
        /// The check itself failed (offline, server).
        case failed(WaiveraError)
    }

    public private(set) var status: Status = .waiting
    public private(set) var failureCount = 0

    @ObservationIgnored private let session: (any SessionRepository)?

    public init(session: (any SessionRepository)?) {
        self.session = session
    }

    public var isChecking: Bool { status == .checking }
    public var canCheck: Bool { session != nil && !isChecking }

    public func observeSession() async {
        guard let session else { return }
        for await state in session.states() {
            apply(state)
        }
    }

    func apply(_ state: SessionState) {
        guard status == .checking else {
            if case .signedOut = state { status = .waiting }
            return
        }
        switch state {
        case .loading, .bootstrapping:
            return
        case .onboardingRequired:
            status = .stillPending
            failureCount += 1
        case .bootstrapFailed(let error):
            status = .failed(error)
            failureCount += 1
        default:
            // Setup finished (the gate moves on by itself) or the session ended.
            status = .waiting
        }
    }

    /// Runs the backend login again. When setup is done the gate moves on by itself; only the
    /// other outcomes are shown here.
    public func checkAgain() async {
        guard canCheck, let session else { return }
        status = .checking
        await session.retryBootstrap()
        // The fake answers synchronously; the live session answers through `states()`.
        apply(session.currentState)
    }
}
