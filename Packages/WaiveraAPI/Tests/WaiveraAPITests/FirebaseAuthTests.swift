import Foundation
import Testing

@testable import WaiveraAPI

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

struct FirebaseAuthRESTTests {
    let signInBody =
        #"{"localId":"uid-1","email":"alex@example.com","displayName":"","idToken":"id-1","#
        + #""registered":true,"refreshToken":"refresh-1","expiresIn":"3600"}"#

    @Test func signInPostsToIdentityToolkitWithTheAPIKey() async throws {
        let transport = StubTransport([.json(signInBody)])
        let clock = ManualClock()
        let auth = FirebaseAuthREST(apiKey: "test-key", transport: transport, clock: clock)
        let session = try await auth.signIn(email: "  alex@example.com ", password: " secret ")
        #expect(session.uid == "uid-1")
        #expect(session.displayName == nil)
        #expect(session.expiresAt == clock.now.addingTimeInterval(3_600))
        let request = try #require(await transport.requests.first)
        #expect(
            request.url?.absoluteString
                == "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=test-key"
        )
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        #expect(body?["email"] as? String == "alex@example.com")
        #expect(body?["password"] as? String == " secret ")
    }

    @Test(arguments: [
        ("INVALID_LOGIN_CREDENTIALS", WaiveraError.AuthFailure.invalidCredentials),
        ("INVALID_PASSWORD", .invalidCredentials),
        ("EMAIL_NOT_FOUND", .invalidCredentials),
        ("USER_DISABLED", .userDisabled),
        ("TOO_MANY_ATTEMPTS_TRY_LATER : Access to this account has been temporarily disabled", .tooManyAttempts),
        ("WEAK_PASSWORD : Password should be at least 6 characters", .weakPassword),
        ("SOMETHING_NEW", .unknown),
    ])
    func mapsProviderCodesWithoutShowingThem(code: String, expected: WaiveraError.AuthFailure) async throws {
        let body = #"{"error":{"code":400,"message":"\#(code)"}}"#
        let auth = FirebaseAuthREST(apiKey: "key", transport: StubTransport([.json(body, status: 400)]))
        await #expect(throws: WaiveraError.auth(expected)) { try await auth.signIn(email: "a@b.c", password: "x") }
        #expect(!WaiveraError.auth(expected).userMessage.contains(code))
    }

    @Test func refreshUsesTheSecureTokenFormBody() async throws {
        let reply = #"{"id_token":"id-2","refresh_token":"refresh-2","expires_in":"3600","user_id":"uid-1"}"#
        let transport = StubTransport([.json(reply)])
        let auth = FirebaseAuthREST(apiKey: "key", transport: transport, clock: ManualClock())
        let old = FirebaseSession(
            uid: "uid-1",
            email: nil,
            displayName: nil,
            idToken: "id-1",
            refreshToken: "a/b+c",
            expiresAt: .distantPast
        )
        let refreshed = try await auth.refresh(old)
        #expect(refreshed.idToken == "id-2")
        #expect(refreshed.refreshToken == "refresh-2")
        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://securetoken.googleapis.com/v1/token?key=key")
        #expect(
            String(decoding: request.httpBody ?? Data(), as: UTF8.self)
                == "grant_type=refresh_token&refresh_token=a%2Fb%2Bc"
        )
    }
}

extension FirebaseAuthRESTTests {
    @Test func passwordResetPostsAnOobCodeRequest() async throws {
        let transport = StubTransport([.json(#"{"email":"alex@example.com"}"#)])
        let auth = FirebaseAuthREST(apiKey: "key", transport: transport)
        try await auth.sendPasswordReset(email: " alex@example.com ")
        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=key")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        #expect(body?["requestType"] as? String == "PASSWORD_RESET")
        #expect(body?["email"] as? String == "alex@example.com")
    }

    @Test func passwordResetForAnUnknownEmailIsInvalidCredentials() async throws {
        let body = #"{"error":{"code":400,"message":"EMAIL_NOT_FOUND"}}"#
        let auth = FirebaseAuthREST(apiKey: "key", transport: StubTransport([.json(body, status: 400)]))
        await #expect(throws: WaiveraError.auth(.invalidCredentials)) {
            try await auth.sendPasswordReset(email: "nobody@example.com")
        }
    }
}

struct FirebaseTokenProviderTests {
    @Test func returnsTheCachedTokenUntilNearExpiryThenRefreshesOnce() async throws {
        let clock = ManualClock()
        let fake = FakeFirebaseAuth(clock: clock)
        let provider = FirebaseTokenProvider(auth: fake, store: InMemoryTokenStore(), clock: clock)
        _ = try await provider.signIn(email: "alex@example.com", password: "pw")
        #expect(try await provider.idToken(forceRefresh: false) == "token-0")
        clock.advance(3_600 - 200)
        async let first = provider.idToken(forceRefresh: false)
        async let second = provider.idToken(forceRefresh: false)
        #expect(try await [first, second] == ["token-1", "token-1"])
        #expect(fake.refreshCount == 1)
        #expect(try await provider.idToken(forceRefresh: true) == "token-2")
    }

    @Test func identityStreamIgnoresTokenRefreshes() async throws {
        let clock = ManualClock()
        let provider = FirebaseTokenProvider(
            auth: FakeFirebaseAuth(clock: clock),
            store: InMemoryTokenStore(),
            clock: clock
        )
        var iterator = provider.identities().makeAsyncIterator()
        #expect(await iterator.next() == .some(nil))
        _ = try await provider.signIn(email: "alex@example.com", password: "pw")
        #expect(await iterator.next()??.uid == "uid-alex")
        _ = try await provider.idToken(forceRefresh: true)
        await provider.signOut()
        // The next value is the sign-out, proving the refresh emitted nothing.
        #expect(await iterator.next() == .some(nil))
    }

    @Test func aDeadRefreshTokenEndsTheSession() async throws {
        let clock = ManualClock()
        let fake = FakeFirebaseAuth(clock: clock)
        let store = InMemoryTokenStore()
        let provider = FirebaseTokenProvider(auth: fake, store: store, clock: clock)
        _ = try await provider.signIn(email: "alex@example.com", password: "pw")
        fake.failRefresh(with: .auth(.sessionExpired))
        await #expect(throws: WaiveraError.unauthorized) { try await provider.idToken(forceRefresh: true) }
        #expect(try await provider.idToken(forceRefresh: false) == nil)
        #expect(try store.load() == nil)
    }

    @Test func anOfflineRefreshKeepsTheSession() async throws {
        let clock = ManualClock()
        let fake = FakeFirebaseAuth(clock: clock)
        let provider = FirebaseTokenProvider(auth: fake, store: InMemoryTokenStore(), clock: clock)
        _ = try await provider.signIn(email: "alex@example.com", password: "pw")
        fake.failRefresh(with: .offline)
        await #expect(throws: WaiveraError.offline) { try await provider.idToken(forceRefresh: true) }
        #expect(await provider.currentIdentity?.uid == "uid-alex")
    }

    @Test func restoresAPersistedSession() async throws {
        let stored = FirebaseSession(
            uid: "uid-alex",
            email: "alex@example.com",
            displayName: nil,
            idToken: "saved",
            refreshToken: "r",
            expiresAt: ManualClock().now.addingTimeInterval(3_000)
        )
        let provider = FirebaseTokenProvider(
            auth: FakeFirebaseAuth(clock: ManualClock()),
            store: InMemoryTokenStore(stored),
            clock: ManualClock()
        )
        #expect(try await provider.idToken(forceRefresh: false) == "saved")
    }
}

final class FakeFirebaseAuth: FirebaseAuthenticating, @unchecked Sendable {
    private let clock: ManualClock
    private let state = LockedValue((refreshes: 0, failure: WaiveraError?.none))

    init(clock: ManualClock) {
        self.clock = clock
    }

    var refreshCount: Int { state.get().refreshes }
    func failRefresh(with error: WaiveraError) { state.update { $0.failure = error } }

    func signIn(email: String, password: String) async throws -> FirebaseSession {
        FirebaseSession(
            uid: "uid-alex",
            email: email,
            displayName: "Alex",
            idToken: "token-0",
            refreshToken: "r0",
            expiresAt: clock.now.addingTimeInterval(3_600)
        )
    }

    func refresh(_ session: FirebaseSession) async throws -> FirebaseSession {
        let (count, failure) = state.update { value -> (Int, WaiveraError?) in
            value.refreshes += 1
            return (value.refreshes, value.failure)
        }
        try await Task.sleep(for: .milliseconds(20))
        if let failure { throw failure }
        var next = session
        next.idToken = "token-\(count)"
        next.expiresAt = clock.now.addingTimeInterval(3_600)
        return next
    }

    func updatePassword(_ newPassword: String, session: FirebaseSession) async throws -> FirebaseSession { session }

    func sendPasswordReset(email: String) async throws {}
}
