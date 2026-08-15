import Foundation

/// Errors surfaced from the API layer.
///
/// `server` carries a stable error `code` (per the shared contract) plus a
/// user-facing message and optional details; `offline` is mapped from
/// `URLError.notConnectedToInternet` and is the only transport-level case UI
/// keys off of.
enum APIError: Error, Equatable, Sendable {
    /// Non-2xx response carrying the uniform error envelope.
    case server(code: String, message: String, details: [String: String] = [:])
    /// No network connectivity (or request dropped before it reached the wire).
    case offline
    /// Decoding failure of a success response.
    case decoding(underlying: String)
    /// The server returned transport error that isn't offline.
    case transport(underlying: String)
    /// A pre-flight request failure not tied to a status code (e.g. bad URL).
    case invalidRequest
    /// Unauthorized and refresh also failed.
    case unauthorized
    /// Unexpected response shape (e.g. empty body where one was expected).
    case unexpected
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .server(code, message, details):
            var parts = ["server(\(code)): \(message)"]
            if !details.isEmpty {
                parts.append(details.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))
            }
            return parts.joined(separator: " ")
        case .offline:
            return "offline: You are offline."
        case let .decoding(msg):
            return "decoding: \(msg)"
        case let .transport(msg):
            return "transport: \(msg)"
        case .invalidRequest:
            return "invalidRequest: Invalid request."
        case .unauthorized:
            return "unauthorized: Session expired."
        case .unexpected:
            return "unexpected: Unexpected response."
        }
    }
}

extension APIError {
    /// The stable error `code` for server errors, otherwise `nil`.
    var code: String? {
        if case let .server(code, _, _) = self { return code }
        return nil
    }

    /// The `details` map for server errors, otherwise empty.
    var details: [String: String] {
        if case let .server(_, _, details) = self { return details }
        return [:]
    }

    /// Human-facing message from the server, otherwise a fallback.
    var message: String {
        switch self {
        case let .server(_, message, _): return message
        case .offline: return "You are offline."
        case let .decoding(msg): return msg
        case let .transport(msg): return msg
        case .invalidRequest: return "Invalid request."
        case .unauthorized: return "Session expired."
        case .unexpected: return "Unexpected response."
        }
    }
}
