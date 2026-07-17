import Foundation
@testable import TimeOfLife

/// Helpers for building decoded payloads and HTTP responses in tests.
enum TestFactories {
    static func user(id: String = "u1", email: String = "a@b.com", verified: Bool = true) -> UserDTO {
        UserDTO(id: id, email: email, emailVerified: verified)
    }

    static func session(accessToken: String = "at", refreshToken: String = "rt",
                        user: UserDTO? = nil) -> AuthSession {
        AuthSession(accessToken: accessToken, refreshToken: refreshToken,
                    user: user ?? self.user())
    }

    static func okResponse(_ url: URL, status: Int = 200, body: Data) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
    }

    static func errorResponse(_ url: URL, status: Int, code: String, message: String,
                              details: [String: Any] = [:]) throws -> (Data, HTTPURLResponse) {
        var payload: [String: Any] = ["code": code, "message": message]
        if !details.isEmpty { payload["details"] = details }
        let body = try JSONSerialization.data(withJSONObject: ["error": payload])
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "application/json"])!
        return (body, resp)
    }

    static func makeURL(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:8080\(path)")!
    }
}