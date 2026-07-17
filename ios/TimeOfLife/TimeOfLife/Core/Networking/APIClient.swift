import Foundation

/// Network client for the auth API.
///
/// Builds `URLRequest`s from `APIEndpoint`s against `baseURL`, attaches a
/// Bearer token from `accessTokenProvider` when `requiresAuth`, decodes
/// either the success body or the uniform error envelope, maps offline via
/// `URLError.notConnectedToInternet`, and on 401 transparently refreshes
/// once via `refreshHandler` and retries the request.
actor APIClient: APISending {
    let baseURL: URL
    let session: URLSession
    let decoder: JSONDecoder
    let encoder: JSONEncoder

    /// Returns the current access token, or `nil` if none. Called lazily per
    /// request that requires auth. Injected so production wires Keychain and
    /// tests wire a stub.
    private let accessTokenProvider: @Sendable () async -> String?
    /// Performs a refresh using the stored refresh token. Returns the new
    /// access token on success, throws on failure. `nil` disables refresh.
    private let refreshHandler: (@Sendable () async throws -> String)?

    init(
        baseURL: URL,
        session: URLSession,
        accessTokenProvider: @escaping @Sendable () async -> String? = { nil },
        refreshHandler: (@Sendable () async throws -> String)? = nil,
        decoder: JSONDecoder = APIClient.defaultDecoder(),
        encoder: JSONEncoder = APIClient.defaultEncoder()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.accessTokenProvider = accessTokenProvider
        self.refreshHandler = refreshHandler
        self.decoder = decoder
        self.encoder = encoder
    }

    static func defaultDecoder() -> JSONDecoder {
        JSONDecoder() // snake_case handled via explicit CodingKeys
    }

    static func defaultEncoder() -> JSONEncoder {
        JSONEncoder() // snake_case handled via explicit CodingKeys
    }

    // MARK: - Public

    /// Sends an endpoint and decodes the success body as `T`.
    func send<T: Decodable & Sendable>(_ endpoint: APIEndpoint, as: T.Type) async throws -> T {
        let data = try await requestData(endpoint, allowRetry: true)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(underlying: String(describing: error))
        }
    }

    /// Sends an endpoint expecting an empty success body (204).
    func sendVoid(_ endpoint: APIEndpoint) async throws {
        let data = try await requestData(endpoint, allowRetry: true)
        if data.isEmpty { return }
        if let str = String(data: data, encoding: .utf8),
           str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return
        }
    }

    // MARK: - Internals

    private func requestData(_ endpoint: APIEndpoint, allowRetry: Bool) async throws -> Data {
        let request = try await makeRequest(endpoint)
        do {
            return try await execute(request)
        } catch APIError.unauthorized where allowRetry {
            guard let refreshHandler else { throw APIError.unauthorized }
            let newToken: String
            do {
                newToken = try await refreshHandler()
            } catch {
                throw APIError.unauthorized
            }
            guard !newToken.isEmpty else { throw APIError.unauthorized }
            let retryRequest = try await makeRequest(endpoint, overrideToken: newToken)
            return try await execute(retryRequest)
        }
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            return try interpret(data: data, response: response)
        } catch let urlError as URLError {
            throw mapURLError(urlError)
        } catch APIError.unauthorized {
            throw APIError.unauthorized
        } catch let apiError as APIError {
            throw apiError
        } catch {
            throw APIError.transport(underlying: String(describing: error))
        }
    }

    private func interpret(data: Data, response: URLResponse) throws -> Data {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.unexpected
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw APIError.unauthorized
        default:
            if !data.isEmpty,
               let env = try? decoder.decode(ErrorEnvelope.self, from: data) {
                throw APIError.server(
                    code: env.error.code,
                    message: env.error.message,
                    details: env.detailsAsHashable
                )
            }
            throw APIError.server(
                code: "http_\(http.statusCode)",
                message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            )
        }
    }

    private func mapURLError(_ error: URLError) -> APIError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff, .timedOut:
            return .offline
        default:
            return .transport(underlying: error.localizedDescription)
        }
    }

    private func makeRequest(_ endpoint: APIEndpoint, overrideToken: String? = nil) async throws -> URLRequest {
        let trimmed = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + endpoint.path) else {
            throw APIError.invalidRequest
        }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = endpoint.body {
            request.httpBody = body
        }
        if endpoint.requiresAuth {
            let token: String?
            if let overrideToken { token = overrideToken } else { token = await accessTokenProvider() }
            if let token, !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
        return request
    }
}

/// Uniform error envelope decoded from any non-2xx response.
struct ErrorEnvelope: Decodable, Sendable {
    struct Body: Decodable, Sendable {
        let code: String
        let message: String
        let details: DetailsEnvelope?
    }
    let error: Body

    var detailsAsHashable: [String: AnyHashable] {
        error.details?.asHashable ?? [:]
    }
}

/// `details` is either a dict or an array in the contract. We accept both,
/// lossy, and expose the dict form.
struct DetailsEnvelope: Decodable, Sendable {
    let raw: AnyCodable

    init(from decoder: Decoder) throws {
        self.raw = try AnyCodable(from: decoder)
    }

    var asHashable: [String: AnyHashable] {
        if let dict = raw.value as? [String: Any] {
            var out: [String: AnyHashable] = [:]
            for (k, v) in dict {
                if let hv = v as? AnyHashable { out[k] = hv }
            }
            return out
        }
        return [:]
    }
}

/// Minimal any-codable for opaque details payloads.
struct AnyCodable: Decodable, Encodable, Sendable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self.value = NSNull() }
        else if let v = try? container.decode(String.self) { self.value = v }
        else if let v = try? container.decode(Double.self) { self.value = v }
        else if let v = try? container.decode(Bool.self) { self.value = v }
        else if let v = try? container.decode([AnyCodable].self) { self.value = v.map { $0.value } }
        else if let v = try? container.decode([String: AnyCodable].self) {
            self.value = v.mapValues { $0.value }
        } else {
            self.value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull: try container.encodeNil()
        case let v as String: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as Bool: try container.encode(v)
        default: try container.encodeNil()
        }
    }
}