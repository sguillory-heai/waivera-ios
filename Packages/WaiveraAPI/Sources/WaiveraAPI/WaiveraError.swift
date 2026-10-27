/// Errors the app can show to a user. Raw server text never reaches the screen.
public enum WaiveraError: Error, Equatable, Sendable {
    case invalidResponse
    case unauthorized
    case server(statusCode: Int)

    public var userMessage: String {
        switch self {
        case .invalidResponse, .server:
            "Something went wrong. Please try again."
        case .unauthorized:
            "Your session has ended. Please sign in again."
        }
    }
}
