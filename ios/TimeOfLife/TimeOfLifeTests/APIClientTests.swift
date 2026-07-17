import Testing
import Foundation
@testable import TimeOfLife

@Suite("APIClient", .serialized)
struct APIClientTests {
    let baseURL = URL(string: "http://127.0.0.1:8080")!

    private func makeClient(
        accessTokenProvider: @escaping @Sendable () async -> String? = { nil },
        refreshHandler: (@Sendable () async throws -> String)? = nil
    ) -> (APIClient, URLSession) {
        let session = URLProtocolStub.makeSession()
        let client = APIClient(baseURL: baseURL, session: session,
                               accessTokenProvider: accessTokenProvider,
                               refreshHandler: refreshHandler)
        return (client, session)
    }

    @Test("decodes success body")
    func successDecode() async throws {
        URLProtocolStub.responseHandler = { request in
            let body = #"{"user":{"id":"u1","email":"a@b.com","email_verified":false}}"#.data(using: .utf8)!
            return (body, TestFactories.okResponse(request.url!, status: 201, body: body))
        }
        let (client, _) = makeClient()
        let resp = try await client.send(
            APIEndpoint(method: .post, path: "/api/v1/auth/signup",
                        body: SignupRequest(email: "a@b.com", password: "abcd1234")),
            as: SignupResponse.self
        )
        #expect(resp.user.id == "u1")
        #expect(resp.user.emailVerified == false)
    }

    @Test("decodes error envelope into APIError.server")
    func errorEnvelope() async throws {
        URLProtocolStub.responseHandler = { request in
            try TestFactories.errorResponse(request.url!, status: 422, code: "email_taken", message: "taken")
        }
        let (client, _) = makeClient()
        await #expect(throws: APIError.self) {
            _ = try await client.send(
                APIEndpoint(method: .post, path: "/api/v1/auth/signup",
                            body: SignupRequest(email: "a@b.com", password: "abcd1234")),
                as: SignupResponse.self
            )
        }
    }

    @Test("offline URLError maps to .offline")
    func offlineMapping() async throws {
        URLProtocolStub.responseHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        let (client, _) = makeClient()
        do {
            _ = try await client.send(
                APIEndpoint.value(method: .get, path: "/api/v1/auth/me"),
                as: UserDTO.self
            )
            Issue.record("expected offline error")
        } catch let error as APIError {
            #expect(error == .offline)
        }
    }

    @Test("401 triggers refresh and retries once with new token")
    func refreshRetry() async throws {
        var calls = 0
        URLProtocolStub.responseHandler = { request in
            calls += 1
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer old" {
                // First attempt: 401
                let body = #"{"error":{"code":"invalid_refresh","message":"x"}}"#.data(using: .utf8)!
                let resp = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!
                return (body, resp)
            }
            // Retry with new token: success
            let body = #"{"id":"u1","email":"a@b.com","email_verified":true}"#.data(using: .utf8)!
            return (body, TestFactories.okResponse(request.url!, status: 200, body: body))
        }
        let (client, _) = makeClient(
            accessTokenProvider: { "old" },
            refreshHandler: { "new" }
        )
        let user = try await client.send(
            APIEndpoint.value(method: .get, path: "/api/v1/auth/me", requiresAuth: true),
            as: UserDTO.self
        )
        #expect(user.id == "u1")
        #expect(calls == 2) // initial + retry
    }

    @Test("401 without refresh handler throws unauthorized")
    func noRefreshThrows() async throws {
        URLProtocolStub.responseHandler = { request in
            let body = Data()
            let resp = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (body, resp)
        }
        let (client, _) = makeClient()
        do {
            _ = try await client.send(
                APIEndpoint.value(method: .get, path: "/api/v1/auth/me", requiresAuth: true),
                as: UserDTO.self
            )
            Issue.record("expected unauthorized")
        } catch let error as APIError {
            #expect(error == .unauthorized)
        }
    }

    @Test("sendVoid tolerates empty 204 body")
    func sendVoidEmpty() async throws {
        URLProtocolStub.responseHandler = { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: "HTTP/1.1", headerFields: nil)!)
        }
        let (client, _) = makeClient()
        try await client.sendVoid(APIEndpoint.value(method: .post, path: "/api/v1/auth/logout", requiresAuth: true))
    }
}