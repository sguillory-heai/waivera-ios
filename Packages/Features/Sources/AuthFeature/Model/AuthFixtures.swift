#if DEBUG
    import Foundation
    import WaiveraAPI
    import WaiveraData
    import WaiveraTestSupport

    /// Prepared models for every screen state, over the fake data environment. Used by previews,
    /// the snapshot tests and the unit tests, so all three show the same states. DEBUG only.
    @MainActor
    public enum AuthFixtures {
        public enum SignIn: String, CaseIterable, Sendable {
            case empty, filled, invalid, failed, unauthorized, connecting, resetSent, configurationMissing
        }

        public enum PasswordChange: String, CaseIterable, Sendable {
            case empty, invalid, wrongCurrent, offline, saving, done
        }

        public enum Bootstrap: String, CaseIterable, Sendable {
            case server, offline, retrying
        }

        public enum Onboarding: String, CaseIterable, Sendable {
            case waiting, checking, stillPending, failed
        }

        public static let email = "alex.rivera@example.org"

        public static func signIn(_ state: SignIn) async -> SignInModel {
            let session = FakeDataEnvironment.make(.signedOut).session
            let reset = FixturePasswordReset()
            switch state {
            case .empty:
                return SignInModel(session: session, passwordReset: reset)
            case .filled:
                let model = SignInModel(session: session, passwordReset: reset)
                model.setEmail(email)
                model.setPassword("correct horse battery")
                return model
            case .invalid:
                let model = SignInModel(session: session, passwordReset: reset)
                model.setEmail("alex.rivera")
                await model.submit()
                return model
            case .failed:
                let model = SignInModel(session: session, passwordReset: reset)
                model.setEmail(email)
                model.setPassword("not the password")
                await model.submit()
                return model
            case .unauthorized:
                let model = SignInModel(session: session, passwordReset: reset)
                model.apply(.signedOut(.unauthorized))
                return model
            case .connecting:
                let model = SignInModel(session: session, passwordReset: reset)
                model.setEmail(email)
                model.setPassword("correct horse battery")
                model.apply(.bootstrapping)
                return model
            case .resetSent:
                let model = SignInModel(session: session, passwordReset: reset)
                model.setEmail(email)
                await model.sendPasswordReset()
                return model
            case .configurationMissing:
                return SignInModel(session: nil)
            }
        }

        public static func passwordChange(
            _ state: PasswordChange,
            mode: PasswordChangeModel.Mode = .required
        ) async -> PasswordChangeModel {
            let fake = FakeDataEnvironment.make(.passwordChange)
            await fake.session.start()
            let model = PasswordChangeModel(mode: mode, session: fake.session)
            switch state {
            case .empty:
                break
            case .invalid:
                model.set(.current, to: FakeSessionRepository.password)
                model.set(.new, to: "short")
                model.set(.confirmation, to: "shorter")
                await model.submit()
            case .wrongCurrent:
                model.set(.current, to: "not the password")
                model.set(.new, to: "a brand new phrase")
                model.set(.confirmation, to: "a brand new phrase")
                await model.submit()
            case .offline:
                let failing = PasswordChangeModel(mode: mode, session: FailingSession(error: .offline))
                failing.set(.current, to: FakeSessionRepository.password)
                failing.set(.new, to: "a brand new phrase")
                failing.set(.confirmation, to: "a brand new phrase")
                await failing.submit()
                return failing
            case .saving:
                let held = PasswordChangeModel(mode: mode, session: HeldSession())
                held.set(.current, to: FakeSessionRepository.password)
                held.set(.new, to: "a brand new phrase")
                held.set(.confirmation, to: "a brand new phrase")
                // Starts the change and leaves it in flight.
                Task { await held.submit() }
                await Task.yield()
                return held
            case .done:
                model.set(.current, to: FakeSessionRepository.password)
                model.set(.new, to: "a brand new phrase")
                model.set(.confirmation, to: "a brand new phrase")
                await model.submit()
            }
            return model
        }

        public static func bootstrap(_ state: Bootstrap) -> BootstrapFailedModel {
            let error: WaiveraError = state == .offline ? .offline : .server(statusCode: 503)
            let session = FailingSession(error: error, state: .bootstrapFailed(error))
            let model = BootstrapFailedModel(session: session, onRetry: {})
            if state == .retrying { model.retry() }
            return model
        }

        public static func onboarding(_ state: Onboarding) async -> OnboardingModel {
            switch state {
            case .waiting:
                return OnboardingModel(session: FailingSession(error: .offline, state: .onboardingRequired(user)))
            case .checking:
                let model = OnboardingModel(session: HeldSession(state: .onboardingRequired(user)))
                Task { await model.checkAgain() }
                await Task.yield()
                return model
            case .stillPending:
                let model = OnboardingModel(session: FailingSession(error: .offline, state: .onboardingRequired(user)))
                await model.checkAgain()
                return model
            case .failed:
                let session = FailingSession(error: .offline, state: .onboardingRequired(user))
                session.retryState = .bootstrapFailed(.offline)
                let model = OnboardingModel(session: session)
                await model.checkAgain()
                return model
            }
        }

        static var user: CurrentUser { DemoData.make().user }
    }

    struct FixturePasswordReset: PasswordResetSending {
        func sendPasswordReset(email: String) async throws {}
    }

    /// A session whose actions fail with one error, sitting in a fixed state.
    final class FailingSession: SessionRepository, @unchecked Sendable {
        private let cell: StateCell<SessionState>
        private let error: WaiveraError
        /// What `retryBootstrap` moves to; the current state when `nil`.
        var retryState: SessionState?

        init(error: WaiveraError, state: SessionState = .signedOut(nil)) {
            self.error = error
            cell = StateCell(state)
        }

        func states() -> AsyncStream<SessionState> { cell.stream() }
        var currentState: SessionState { cell.current }
        func start() async {}
        func signIn(email: String, password: String) async throws { throw error }
        func changePassword(current: String, new: String) async throws { throw error }
        func retryBootstrap() async {
            if let retryState { cell.set(retryState) }
        }
        func signOut() async { cell.set(.signedOut(nil)) }
    }

    /// A session whose actions never finish, for the busy states.
    final class HeldSession: SessionRepository, @unchecked Sendable {
        private let cell: StateCell<SessionState>

        init(state: SessionState = .signedOut(nil)) {
            cell = StateCell(state)
        }

        func states() -> AsyncStream<SessionState> { cell.stream() }
        var currentState: SessionState { cell.current }
        func start() async {}
        func signIn(email: String, password: String) async throws { try await hold() }
        func changePassword(current: String, new: String) async throws { try await hold() }
        func retryBootstrap() async { try? await hold() }
        func signOut() async { cell.set(.signedOut(nil)) }

        private func hold() async throws {
            try await Task.sleep(for: .seconds(3600))
        }
    }
#endif
