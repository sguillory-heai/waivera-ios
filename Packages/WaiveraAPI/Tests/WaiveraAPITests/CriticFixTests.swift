import Foundation
import Testing

@testable import WaiveraAPI

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Fixes for the iOS functional and security reviews (IF-05, IF-08, IS-02, IS-03, IS-10).
@Suite("Critic fixes: auth and API")
struct CriticFixTests {
    private let signInBody =
        #"{"localId":"uid-1","email":"alex@example.com","idToken":"id-1","#
        + #""refreshToken":"refresh-1","expiresIn":"3600"}"#

    private func signedInProvider(refreshReply: StubTransport.Reply) async throws -> (
        FirebaseTokenProvider, InMemoryTokenStore
    ) {
        let clock = ManualClock()
        let transport = StubTransport([.json(signInBody), refreshReply])
        let store = InMemoryTokenStore()
        let provider = FirebaseTokenProvider(
            auth: FirebaseAuthREST(apiKey: "key", transport: transport, clock: clock),
            store: store,
            clock: clock
        )
        _ = try await provider.signIn(email: "alex@example.com", password: "pw")
        return (provider, store)
    }

    // MARK: IS-02

    @Test("IS-02: a rate-limited refresh keeps the session and is retryable")
    func rateLimitedRefreshKeepsTheSession() async throws {
        let body = #"{"error":{"code":400,"message":"TOO_MANY_ATTEMPTS_TRY_LATER"}}"#
        let (provider, store) = try await signedInProvider(refreshReply: .json(body, status: 400))
        await #expect(throws: WaiveraError.server(statusCode: 429)) { try await provider.idToken(forceRefresh: true) }
        #expect(WaiveraError.server(statusCode: 429).isTransient)
        #expect(await provider.currentIdentity?.uid == "uid-1")
        #expect(try store.load() != nil)
    }

    @Test("IS-02: an HTML 403 from a captive portal keeps the session")
    func captivePortalRefreshKeepsTheSession() async throws {
        let (provider, store) = try await signedInProvider(refreshReply: .json("<html>Sign in to Wi-Fi</html>", status: 403))
        await #expect(throws: WaiveraError.server(statusCode: 503)) { try await provider.idToken(forceRefresh: true) }
        #expect(await provider.currentIdentity?.uid == "uid-1")
        #expect(try store.load() != nil)
    }

    @Test(
        "IS-02: a revoked refresh token or a disabled user still ends the session",
        arguments: ["INVALID_REFRESH_TOKEN", "USER_DISABLED", "TOKEN_EXPIRED", "INVALID_GRANT_TYPE"]
    )
    func terminalRefreshCodesEndTheSession(code: String) async throws {
        let body = #"{"error":{"code":400,"message":"\#(code)"}}"#
        let (provider, store) = try await signedInProvider(refreshReply: .json(body, status: 400))
        await #expect(throws: WaiveraError.unauthorized) { try await provider.idToken(forceRefresh: true) }
        #expect(await provider.currentIdentity == nil)
        #expect(try store.load() == nil)
    }

    // MARK: IS-03

    @Test("IS-03: a locked Keychain is not signed out, and the session returns after unlock")
    func lockedStoreWaitsForUnlock() async throws {
        let stored = FirebaseSession(
            uid: "uid-alex",
            email: nil,
            displayName: nil,
            idToken: "saved",
            refreshToken: "r",
            expiresAt: ManualClock().now.addingTimeInterval(3_000)
        )
        let store = InMemoryTokenStore(stored)
        store.setLocked(true)
        let clock = ManualClock()
        let provider = FirebaseTokenProvider(auth: FakeFirebaseAuth(clock: clock), store: store, clock: clock)
        let identities = provider.identities()
        let first = Task { () -> FirebaseIdentity?? in
            var iterator = identities.makeAsyncIterator()
            return await iterator.next()
        }
        // Locked: no identity at all (in particular no `nil`), and requests are retryable.
        await #expect(throws: WaiveraError.offline) { try await provider.idToken(forceRefresh: false) }
        try await Task.sleep(for: .milliseconds(20))
        #expect(await provider.currentIdentity == nil)
        store.setLocked(false)
        await provider.reloadStoredSession()
        #expect(await first.value == .some(FirebaseIdentity(uid: "uid-alex", email: nil, displayName: nil)))
        #expect(try await provider.idToken(forceRefresh: false) == "saved")
        #expect(try store.load() == stored)
    }

    // MARK: IS-10

    @Test("IS-10: every identitytoolkit and securetoken request carries the bundle id")
    func bundleHeaderOnEveryRequest() async throws {
        let refreshReply = #"{"id_token":"id-2","refresh_token":"refresh-2","expires_in":"3600"}"#
        let transport = StubTransport([.json(signInBody), .json(refreshReply), .json(#"{"email":"a@b.c"}"#)])
        let auth = FirebaseAuthREST(apiKey: "key", bundleIdentifier: "com.waivera.waivera", transport: transport)
        let session = try await auth.signIn(email: "alex@example.com", password: "pw")
        _ = try await auth.refresh(session)
        try await auth.sendPasswordReset(email: "alex@example.com")
        let headers = await transport.requests.map { $0.value(forHTTPHeaderField: "X-Ios-Bundle-Identifier") }
        #expect(headers == ["com.waivera.waivera", "com.waivera.waivera", "com.waivera.waivera"])
    }

    @Test("IS-10: the bundle id comes from configuration")
    func bundleIdentifierFromConfiguration() throws {
        let configuration = try WaiveraConfiguration.load(from: [
            "WaiveraAPIBaseURL": "https://api.example.test",
            "WaiveraFirebaseAPIKey": "key",
            "CFBundleIdentifier": "com.waivera.waivera",
        ]).get()
        #expect(configuration.bundleIdentifier == "com.waivera.waivera")
    }

    // MARK: IF-05

    @Test("IF-05: a 401 that survives the token refresh reports a rejected session")
    func persistentUnauthorizedIsReported() async throws {
        let transport = StubTransport([.empty(401), .empty(401)])
        let client = try makeClient(transport)
        let reports = Task { () -> Int? in
            var iterator = client.rejections.stream().makeAsyncIterator()
            return await iterator.next()
        }
        try await Task.sleep(for: .milliseconds(10))
        await #expect(throws: WaiveraError.unauthorized) { try await client.send(APIRequest(.get, "api/chat/all")) }
        #expect(await reports.value == 1)
    }

    @Test("IF-05: a 401 fixed by the refresh, a 403 or a 5xx is not a rejected session")
    func recoverableFailuresAreNotReported() async throws {
        let transport = StubTransport([.empty(401), .empty(200), .empty(403), .empty(503)])
        let client = try makeClient(transport)
        let reports = Task { () -> Int? in
            var iterator = client.rejections.stream().makeAsyncIterator()
            return await iterator.next()
        }
        try await Task.sleep(for: .milliseconds(10))
        try await client.send(APIRequest(.get, "api/chat/all"))
        await #expect(throws: WaiveraError.forbidden) { try await client.send(APIRequest(.get, "api/chat/all")) }
        await #expect(throws: WaiveraError.server(statusCode: 503)) {
            try await client.send(APIRequest(.get, "api/chat/all"))
        }
        try await Task.sleep(for: .milliseconds(20))
        reports.cancel()
        #expect(await reports.value == nil)
    }

    // MARK: IF-08

    @Test("IF-08: a login without a user id fails instead of carrying an empty id")
    func loginWithoutUserIdFails() {
        let body = Data(#"{"requiresPasswordChange":false,"requiresOnboarding":false}"#.utf8)
        #expect(throws: DecodingError.self) { try WaiveraJSON.decoder().decode(UserLoginResponseDto.self, from: body) }
        let blank = Data(#"{"userId":" "}"#.utf8)
        #expect(throws: DecodingError.self) { try WaiveraJSON.decoder().decode(UserLoginResponseDto.self, from: blank) }
    }

    @Test("IF-08: a PascalCase UserID is accepted")
    func pascalCaseUserIdDecodes() throws {
        let body = Data(#"{"UserID":"usr_alex_rivera","RequiresOnboarding":true}"#.utf8)
        let login = try WaiveraJSON.decoder().decode(UserLoginResponseDto.self, from: body)
        #expect(login.userId == "usr_alex_rivera")
        #expect(login.requiresOnboarding)
    }

    @Test("IF-08: a login envelope without a user id is an invalid response")
    func enveloppedLoginWithoutUserIdIsInvalid() async throws {
        let transport = StubTransport([.json(#"{"data":{"requiresOnboarding":false},"success":true}"#)])
        let client = try makeClient(transport)
        await #expect(throws: WaiveraError.invalidResponse) { try await client.login() }
    }
}
