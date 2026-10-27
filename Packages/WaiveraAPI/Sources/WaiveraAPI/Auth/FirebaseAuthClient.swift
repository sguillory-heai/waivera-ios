import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A signed-in Firebase user as the app keeps it. Only a summary, never provider objects.
public struct FirebaseSession: Codable, Sendable, Equatable {
    public var uid: String
    public var email: String?
    public var displayName: String?
    public var idToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(
        uid: String,
        email: String?,
        displayName: String?,
        idToken: String,
        refreshToken: String,
        expiresAt: Date
    ) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.idToken = idToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

/// Firebase Auth email/password, behind a protocol so tests and demo mode can fake it.
/// All thrown errors are `WaiveraError` (`.auth(...)`, `.offline`, `.invalidResponse`).
public protocol FirebaseAuthenticating: Sendable {
    func signIn(email: String, password: String) async throws -> FirebaseSession
    func refresh(_ session: FirebaseSession) async throws -> FirebaseSession
    func updatePassword(_ newPassword: String, session: FirebaseSession) async throws -> FirebaseSession
    /// Sends Firebase's password reset email. `EMAIL_NOT_FOUND` maps to `.auth(.invalidCredentials)`,
    /// so a caller can show the same "sent" copy and never reveal whether an account exists.
    func sendPasswordReset(email: String) async throws
}

/// The Firebase Auth REST API over URLSession (identitytoolkit + securetoken), so sign-in is
/// Linux-testable and needs no Firebase SDK in this package.
public struct FirebaseAuthREST: FirebaseAuthenticating {
    public struct Endpoints: Sendable {
        public var identityToolkit: URL
        public var secureToken: URL

        public init(identityToolkit: URL, secureToken: URL) {
            self.identityToolkit = identityToolkit
            self.secureToken = secureToken
        }

        /// Google's public endpoints. Not environment-specific: the project is chosen by the API key.
        public static var google: Endpoints {
            Endpoints(
                identityToolkit: URL(string: "https://identitytoolkit.googleapis.com/v1/") ?? URL(fileURLWithPath: "/"),
                secureToken: URL(string: "https://securetoken.googleapis.com/v1/") ?? URL(fileURLWithPath: "/")
            )
        }
    }

    /// Google checks this header when the API key is restricted to iOS apps (IS-10).
    static let bundleHeader = "X-Ios-Bundle-Identifier"

    private let apiKey: String
    private let bundleIdentifier: String?
    private let transport: any HTTPTransport
    private let clock: any WaiveraClock
    private let endpoints: Endpoints

    /// `bundleIdentifier` is the app's bundle id from configuration; it is sent on every call so
    /// the Firebase key can be restricted to this app.
    public init(
        apiKey: String,
        bundleIdentifier: String? = nil,
        transport: any HTTPTransport = URLSession.shared,
        clock: any WaiveraClock = SystemClock(),
        endpoints: Endpoints = .google
    ) {
        self.apiKey = apiKey
        self.bundleIdentifier = bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 }
        self.transport = transport
        self.clock = clock
        self.endpoints = endpoints
    }

    public func signIn(email: String, password: String) async throws -> FirebaseSession {
        let body = PasswordSignInBody(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
        let response: IdentityToolkitResponse = try await post(
            url: APIClient.join(endpoints.identityToolkit, "accounts:signInWithPassword"),
            json: body
        )
        return response.session(issuedAt: clock.now)
    }

    public func refresh(_ session: FirebaseSession) async throws -> FirebaseSession {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let token = session.refreshToken.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        var request = URLRequest(url: keyed(APIClient.join(endpoints.secureToken, "token")))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("grant_type=refresh_token&refresh_token=\(token)".utf8)
        let response: SecureTokenResponse = try await perform(request)
        var refreshed = session
        refreshed.idToken = response.idToken
        refreshed.refreshToken = response.refreshToken
        refreshed.expiresAt = clock.now.addingTimeInterval(TimeInterval(response.expiresIn) ?? 3_600)
        return refreshed
    }

    public func updatePassword(_ newPassword: String, session: FirebaseSession) async throws -> FirebaseSession {
        let body = UpdatePasswordBody(idToken: session.idToken, password: newPassword)
        let response: IdentityToolkitResponse = try await post(
            url: APIClient.join(endpoints.identityToolkit, "accounts:update"),
            json: body
        )
        var updated = response.session(issuedAt: clock.now)
        updated.email = updated.email ?? session.email
        updated.displayName = updated.displayName ?? session.displayName
        return updated
    }

    public func sendPasswordReset(email: String) async throws {
        let body = PasswordResetBody(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
        let _: PasswordResetResponse = try await post(
            url: APIClient.join(endpoints.identityToolkit, "accounts:sendOobCode"),
            json: body
        )
    }

    private func keyed(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        return components?.url ?? url
    }

    private func post<Body: Encodable, Response: Decodable>(url: URL, json body: Body) async throws -> Response {
        var request = URLRequest(url: keyed(url))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        var request = request
        if let bundleIdentifier { request.setValue(bundleIdentifier, forHTTPHeaderField: Self.bundleHeader) }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw WaiveraError.from(error)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw FirebaseAuthErrorMapper.map(statusCode: response.statusCode, body: data)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw WaiveraError.invalidResponse
        }
    }
}

/// Maps Firebase REST error codes to `WaiveraError.auth`. Provider text is never shown (01 §3).
public enum FirebaseAuthErrorMapper {
    public static func map(statusCode: Int, body: Data) -> WaiveraError {
        guard let envelope = try? JSONDecoder().decode(FirebaseErrorEnvelope.self, from: body) else {
            return statusCode >= 500 ? .server(statusCode: statusCode) : .auth(.unknown)
        }
        let code = envelope.error.message.split(separator: " ").first.map(String.init) ?? ""
        return .auth(failure(for: code))
    }

    static func failure(for code: String) -> WaiveraError.AuthFailure {
        switch code {
        case "EMAIL_NOT_FOUND", "INVALID_PASSWORD", "INVALID_LOGIN_CREDENTIALS", "MISSING_PASSWORD":
            .invalidCredentials
        case "INVALID_EMAIL", "MISSING_EMAIL": .invalidEmail
        case "USER_DISABLED": .userDisabled
        case "TOO_MANY_ATTEMPTS_TRY_LATER": .tooManyAttempts
        case "WEAK_PASSWORD": .weakPassword
        case "CREDENTIAL_TOO_OLD_LOGIN_AGAIN": .requiresRecentLogin
        case "TOKEN_EXPIRED", "INVALID_ID_TOKEN", "INVALID_REFRESH_TOKEN", "USER_NOT_FOUND", "MISSING_REFRESH_TOKEN",
            "INVALID_GRANT_TYPE", "PROJECT_NUMBER_MISMATCH":
            .sessionExpired
        default: .unknown
        }
    }
}

private struct FirebaseErrorEnvelope: Decodable {
    struct Detail: Decodable { var message: String }
    var error: Detail
}

private struct PasswordSignInBody: Encodable {
    var email: String
    var password: String
    var returnSecureToken = true
}

private struct UpdatePasswordBody: Encodable {
    var idToken: String
    var password: String
    var returnSecureToken = true
}

private struct PasswordResetBody: Encodable {
    var requestType = "PASSWORD_RESET"
    var email: String
}

private struct PasswordResetResponse: Decodable {
    var email: String?
}

private struct IdentityToolkitResponse: Decodable {
    var localId: String
    var email: String?
    var displayName: String?
    var idToken: String
    var refreshToken: String
    var expiresIn: String?

    func session(issuedAt now: Date) -> FirebaseSession {
        let lifetime = expiresIn.flatMap(TimeInterval.init) ?? 3_600
        let name = displayName.flatMap { $0.isEmpty ? nil : $0 }
        return FirebaseSession(
            uid: localId,
            email: email,
            displayName: name,
            idToken: idToken,
            refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(lifetime)
        )
    }
}

private struct SecureTokenResponse: Decodable {
    var idToken: String
    var refreshToken: String
    var expiresIn: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}
