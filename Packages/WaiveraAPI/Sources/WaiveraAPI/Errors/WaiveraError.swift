import Foundation

/// Errors the app can show to a user. Raw server or provider text never reaches the
/// screen: every case has client-owned copy in `userMessage`, and the server's own
/// message is only used internally to pick a case (gap G-12).
public enum WaiveraError: Error, Equatable, Hashable, Sendable, Codable {
    /// No network, a timeout, or the connection dropped mid-request.
    case offline
    /// Signed out locally; the request was never sent.
    case signedOut
    /// 401 after one forced token refresh, or the backend rejected the Firebase identity.
    case unauthorized
    /// 403: no access to this resource, or the account is suspended.
    case forbidden
    case notFound
    /// 409 from a concurrent update.
    case conflict
    /// 400 the client cannot fix by retrying.
    case invalidRequest
    /// 5xx, or any other unexpected status.
    case server(statusCode: Int)
    /// The response could not be decoded or was not what the contract promises.
    case invalidResponse
    /// Base URL or Firebase API key missing from the build configuration.
    case configurationMissing
    case channelArchived
    case channelReadOnly
    /// Reactions (gap G-01) and other hub-only actions need a live connection.
    case realtimeUnavailable
    /// 423: the attachment failed security scanning.
    case attachmentBlocked
    /// The attachment is still being scanned.
    case attachmentPending
    case attachmentUploadFailed
    case auth(AuthFailure)

    /// Firebase Auth failures, mapped from the REST error codes.
    public enum AuthFailure: String, Sendable, Hashable, Codable {
        case invalidCredentials
        case invalidEmail
        case userDisabled
        case tooManyAttempts
        case weakPassword
        case requiresRecentLogin
        case sessionExpired
        case unknown

        /// Whether a token refresh that failed this way means the session is over for good
        /// (revoked or invalid refresh token, disabled or deleted user). Everything else, rate
        /// limiting and unknown codes included, may succeed later (IS-02).
        public var endsSession: Bool {
            switch self {
            case .sessionExpired, .userDisabled: true
            default: false
            }
        }
    }

    /// Short, user-facing copy, from `Localizable.strings` in this package.
    public var userMessage: String {
        switch self {
        case .offline: localized("error.offline")
        case .signedOut, .unauthorized: localized("error.unauthorized")
        case .forbidden: localized("error.forbidden")
        case .notFound: localized("error.notFound")
        case .conflict: localized("error.conflict")
        case .invalidRequest: localized("error.invalidRequest")
        case .server, .invalidResponse: localized("error.generic")
        case .configurationMissing: localized("error.configurationMissing")
        case .channelArchived: localized("error.channelArchived")
        case .channelReadOnly: localized("error.channelReadOnly")
        case .realtimeUnavailable: localized("error.realtimeUnavailable")
        case .attachmentBlocked: localized("error.attachmentBlocked")
        case .attachmentPending: localized("error.attachmentPending")
        case .attachmentUploadFailed: localized("error.attachmentUploadFailed")
        case .auth(let failure): localized("error.auth.\(failure.rawValue)")
        }
    }

    /// Whether retrying the same request later can succeed without user action.
    public var isTransient: Bool {
        switch self {
        case .offline, .realtimeUnavailable, .attachmentPending: true
        case .server(let status): status >= 500 || status == 408 || status == 429
        default: false
        }
    }

    /// Maps any thrown error to a `WaiveraError`; unknown errors become `.invalidResponse`
    /// rather than leaking their description.
    public static func from(_ error: any Error) -> WaiveraError {
        if let error = error as? WaiveraError { return error }
        if error is DecodingError { return .invalidResponse }
        if error is CancellationError { return .offline }
        if let urlError = error as? URLError { return from(urlError) }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return .offline }
        return .invalidResponse
    }

    private static func from(_ error: URLError) -> WaiveraError {
        switch error.code {
        case .userAuthenticationRequired: .unauthorized
        case .badServerResponse, .cannotParseResponse, .cannotDecodeContentData: .invalidResponse
        default: .offline
        }
    }

    private func localized(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }
}
