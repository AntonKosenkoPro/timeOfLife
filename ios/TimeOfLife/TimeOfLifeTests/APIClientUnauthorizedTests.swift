import Testing
import Foundation
@testable import TimeOfLife

@Suite("APIClient unauthorized handling", .serialized)
struct APIClientUnauthorizedTests {

    let baseURL = URL(string: "http://127.0.0.1:8080")!

    private func makeClient(
        accessTokenProvider: @escaping @Sendable () async -> String? = { nil },
        refreshHandler: (@Sendable () async throws -> String)? = nil
    ) -> APIClient {
        APIClient(
            baseURL: baseURL,
            session: URLProtocolStub.makeSession(),
            accessTokenProvider: accessTokenProvider,
            refreshHandler: refreshHandler
        )
    }

    @Test("public 401 does not consume the refresh token")
    func publicUnauthorizedDoesNotRefresh() async throws {
        defer { URLProtocolStub.clear() }

        URLProtocolStub.responseHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401,
                httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (Data(), response)
        }
        var refreshCalls = 0
        let client = makeClient {
            refreshCalls += 1
            return "new"
        }

        do {
            try await client.send(
                APIEndpoint.value(method: .get, path: "/api/v1/auth/me"),
                as: UserDTO.self
            )
            Issue.record("Expected unauthorized error")
        } catch let error as APIError {
            #expect(error == .unauthorized)
        }
        #expect(refreshCalls == 0)
    }

    @Test("refresh errors are preserved for offline recovery")
    func refreshErrorIsPreserved() async throws {
        defer { URLProtocolStub.clear() }

        URLProtocolStub.responseHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401,
                httpVersion: "HTTP/1.1", headerFields: nil
            )!
            return (Data(), response)
        }
        let client = makeClient(
            accessTokenProvider: { "expired" },
            refreshHandler: { throw APIError.offline }
        )

        do {
            try await client.send(
                APIEndpoint.value(method: .get, path: "/api/v1/auth/me", requiresAuth: true),
                as: UserDTO.self
            )
            Issue.record("Expected offline error")
        } catch let error as APIError {
            #expect(error == .offline)
        }
    }
}
