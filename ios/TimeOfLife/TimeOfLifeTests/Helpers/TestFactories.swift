import Foundation
@testable import TimeOfLife

/// Helpers for building decoded payloads and HTTP responses in tests.
enum TestFactories {

    // MARK: - Model factories

    /// Creates a `UserDTO` with sensible defaults.
    static func makeUser(
        id: String = "u1",
        email: String = "user@example.com",
        emailVerified: Bool = true
    ) -> UserDTO {
        UserDTO(id: id, email: email, emailVerified: emailVerified)
    }

    /// Creates an `AuthSession` with sensible defaults.
    static func makeAuthResponse(
        accessToken: String = "access_token_abc",
        refreshToken: String = "refresh_token_xyz",
        user: UserDTO? = nil
    ) -> AuthSession {
        AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            user: user ?? makeUser()
        )
    }

    /// Creates a JSON-encoded error envelope matching the server contract.
    static func makeErrorResponse(
        code: String,
        message: String,
        details: [String: Any] = [:]
    ) -> Data {
        var payload: [String: Any] = ["code": code, "message": message]
        if !details.isEmpty {
            payload["details"] = details
        }
        let envelope: [String: Any] = ["error": payload]
        return (try? JSONSerialization.data(withJSONObject: envelope)) ?? Data()
    }

    // MARK: - Input factories

    static func makeValidEmail() -> String { "user@example.com" }
    static func makeInvalidEmail() -> String { "not-an-email" }
    static func makeValidOTP() -> String { "123456" }
    static func makeInvalidOTP() -> String { "abc" }

    // MARK: - HTTP response factories

    /// Creates a 200 `HTTPURLResponse` for the given URL.
    static func okResponse(
        _ url: URL,
        status: Int = 200,
        body: Data = Data()
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    /// Creates an error `HTTPURLResponse` with a JSON error envelope body.
    static func errorResponse(
        _ url: URL,
        status: Int,
        code: String,
        message: String,
        details: [String: Any] = [:]
    ) -> (Data, HTTPURLResponse) {
        let body = makeErrorResponse(code: code, message: message, details: details)
        let resp = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (body, resp)
    }

    static func makeURL(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:8080\(path)")!
    }
}
