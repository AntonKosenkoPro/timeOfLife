import Foundation
import Vapor

// MARK: - Error envelope

/// Uniform error response shape: `{ "error": { "code": "...", "message": "...", "details": {...} } }`
struct ErrorEnvelope: Content {
    let error: Body
    struct Body: Content {
        let code: String
        let message: String
        let details: [String: String]
    }
}

// MARK: - Abortable

/// Domain errors adopt `Abortable` to map cleanly to HTTP responses with our envelope.
protocol Abortable: Error {
    var errorCode: String { get }
    var httpStatus: HTTPResponseStatus { get }
    var message: String { get }
    var details: [String: String] { get }
}

extension Abortable {
    var message: String { errorCode.replacingOccurrences(of: "_", with: " ").capitalized }
    var details: [String: String] { [:] }

    /// Convert to a Vapor response using our uniform error envelope.
    func makeResponse(_ req: Request) -> Response {
        let body = ErrorEnvelope.Body(code: errorCode, message: message, details: details)
        let envelope = ErrorEnvelope(error: body)
        let response = Response(status: httpStatus)
        response.headers.add(name: .contentType, value: "application/json; charset=utf-8")
        if let data = try? JSONEncoder().encode(envelope) {
            response.body = Response.Body(data: data)
        }
        return response
    }
}

// MARK: - Domain errors

enum AuthError: Abortable {
    case invalidBody
    case emailTaken
    case weakPassword(rules: [String])
    case invalidCredentials
    case emailNotVerified
    case invalidRefresh
    case tokenExpired
    case tokenReuse
    case unauthorized

    var errorCode: String {
        switch self {
        case .invalidBody: return "invalid_body"
        case .emailTaken: return "email_taken"
        case .weakPassword: return "weak_password"
        case .invalidCredentials: return "invalid_credentials"
        case .emailNotVerified: return "email_not_verified"
        case .invalidRefresh: return "invalid_refresh"
        case .tokenExpired: return "token_expired"
        case .tokenReuse: return "token_reuse"
        case .unauthorized: return "unauthorized"
        }
    }

    var httpStatus: HTTPResponseStatus {
        switch self {
        case .invalidBody: return .badRequest
        case .emailTaken: return .unprocessableEntity
        case .weakPassword: return .unprocessableEntity
        case .invalidCredentials: return .unauthorized
        case .emailNotVerified: return .forbidden
        case .invalidRefresh: return .unauthorized
        case .tokenExpired: return .unauthorized
        case .tokenReuse: return .unauthorized
        case .unauthorized: return .unauthorized
        }
    }

    var message: String {
        switch self {
        case .invalidBody: return "Request body is invalid or malformed."
        case .emailTaken: return "An account with this email already exists."
        case .weakPassword: return "Password does not meet strength requirements."
        case .invalidCredentials: return "Invalid email or password."
        case .emailNotVerified: return "Email is not verified. Please verify your email before signing in."
        case .invalidRefresh: return "Refresh token is invalid."
        case .tokenExpired: return "Refresh token has expired."
        case .tokenReuse: return "Refresh token reuse detected. All sessions have been revoked."
        case .unauthorized: return "Authentication required."
        }
    }

    var details: [String: String] {
        switch self {
        case .weakPassword(let rules):
            return ["rules": rules.joined(separator: ",")]
        default:
            return [:]
        }
    }
}

enum VerifyError: Abortable {
    case tokenInvalid
    case tokenExpired
    case tokenUsed

    var errorCode: String {
        switch self {
        case .tokenInvalid: return "verify_token_invalid"
        case .tokenExpired: return "verify_token_expired"
        case .tokenUsed: return "verify_token_used"
        }
    }
    var httpStatus: HTTPResponseStatus {
        switch self {
        case .tokenInvalid: return .notFound
        case .tokenExpired: return .gone
        case .tokenUsed: return .conflict
        }
    }
}

enum ResetError: Abortable {
    case tokenInvalid
    case tokenExpired
    case tokenUsed
    case weakPassword(rules: [String])

    var errorCode: String {
        switch self {
        case .tokenInvalid: return "reset_token_invalid"
        case .tokenExpired: return "reset_token_expired"
        case .tokenUsed: return "reset_token_used"
        case .weakPassword: return "weak_password"
        }
    }
    var httpStatus: HTTPResponseStatus {
        switch self {
        case .tokenInvalid: return .notFound
        case .tokenExpired: return .gone
        case .tokenUsed: return .conflict
        case .weakPassword: return .unprocessableEntity
        }
    }
    var message: String {
        switch self {
        case .tokenInvalid: return "Reset token is invalid."
        case .tokenExpired: return "Reset token has expired."
        case .tokenUsed: return "Reset token has already been used."
        case .weakPassword: return "Password does not meet strength requirements."
        }
    }
    var details: [String: String] {
        switch self {
        case .weakPassword(let rules): return ["rules": rules.joined(separator: ",")]
        default: return [:]
        }
    }
}

enum RateLimitError: Abortable {
    case throttled(retryAfter: Int)

    var errorCode: String { "rate_limited" }
    var httpStatus: HTTPResponseStatus { .tooManyRequests }
    var message: String { "Too many requests. Please retry later." }
    var details: [String: String] {
        switch self {
        case .throttled(let s): return ["retry_after": "\(s)"]
        }
    }
}

// MARK: - AbortError conformance bridging to our envelope

struct DomainAbortError: AbortError {
    let error: Abortable
    var status: HTTPResponseStatus { error.httpStatus }
    var reason: String { error.message }
    var headers: HTTPHeaders { HTTPHeaders() }
    init(_ error: Abortable) { self.error = error }
}

extension Abortable {
    func abort() -> AbortError { DomainAbortError(self) }
}

extension Vapor.Application {
    /// Install a custom default error transformer that wraps any error in our envelope.
    func installErrorTransformer() {
        // Hook the default error handler via a custom responder hook on Response.
        // Simpler: register a custom error on app via middleware in routes; see ErrorsMiddleware.
    }
}