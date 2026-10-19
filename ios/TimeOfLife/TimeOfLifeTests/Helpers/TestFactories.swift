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

    /// Creates a durable `CredentialSnapshot` with sensible defaults.
    static func makeSnapshot(
        accessToken: String = "at",
        refreshToken: String = "rt",
        accountId: String = "u1",
        deviceId: String? = "device-1",
        pendingAttemptId: String? = nil,
        pendingPredecessor: String? = nil
    ) -> CredentialSnapshot {
        CredentialSnapshot(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountId: accountId,
            deviceId: deviceId,
            pendingAttemptId: pendingAttemptId,
            pendingPredecessor: pendingPredecessor
        )
    }

    /// Reads the durable token pair (plus pending attempt) from a keychain.
    /// Returns nils when storage is unavailable or no snapshot exists.
    static func snapshotTokens(_ keychain: InMemoryKeychainStore) async -> (
        access: String?, refresh: String?, attempt: String?
    ) {
        guard case .success(let snapshot) = await keychain.loadSnapshot() else {
            return (nil, nil, nil)
        }
        return (snapshot?.accessToken, snapshot?.refreshToken, snapshot?.pendingAttemptId)
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

    // MARK: - HTTP response factories

    /// Creates a 200 `HTTPURLResponse` for the given URL.
    static func okResponse(
        _ url: URL,
        status: Int = 200
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

    // MARK: - Service factories

    /// Builds a wired-up `AuthService` with in-memory stores for view-model tests.
    @MainActor
    static func makeService(
        repo: FakeAuthRepository = FakeAuthRepository()
    ) -> (AuthService, FakeAuthRepository, Connectivity, SessionStore) {
        let keychain = InMemoryKeychainStore()
        let cache = SessionCache(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let store = SessionStore()
        let service = AuthService(
            repository: repo,
            keychain: keychain,
            cache: cache,
            sessionStore: store
        )
        return (service, repo, Connectivity(), store)
    }
}
