import Foundation

/// URLProtocol subclass that serves canned responses for `APIClient` tests.
///
/// Supports two modes:
/// 1. **Stub-based** — `stub(data:for:)`, `stub(error:for:)`, `stub(statusCode:for:)`
///    map responses by URL. Thread-safe.
/// 2. **Closure-based** — `responseHandler` receives the full `URLRequest` and
///    returns a `(Data, HTTPURLResponse)` tuple. Useful for multi-step scenarios
///    (e.g. 401 retry) where the response depends on request headers.
///
/// Call `clear()` between tests to reset all state.
final class URLProtocolStub: URLProtocol {

    // MARK: - Stored stubs

    private static var stubs: [URL: Stub] = [:]
    private static var lock = os_unfair_lock()

    /// Closure-based handler for complex scenarios. When set, takes precedence
    /// over the stub dictionary.
    nonisolated(unsafe) static var responseHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    /// A canned response for a given URL.
    private enum Stub {
        case data(Data, statusCode: Int)
        case error(Error)
    }

    // MARK: - Public API

    /// Stubs the given URL to return `data` with a 200 status code.
    static func stub(data: Data, for url: URL) {
        os_unfair_lock_lock(&lock)
        stubs[url] = .data(data, statusCode: 200)
        os_unfair_lock_unlock(&lock)
    }

    /// Stubs the given URL to return `data` with the given status code.
    static func stub(data: Data, statusCode: Int, for url: URL) {
        os_unfair_lock_lock(&lock)
        stubs[url] = .data(data, statusCode: statusCode)
        os_unfair_lock_unlock(&lock)
    }

    /// Stubs the given URL to throw `error`.
    static func stub(error: Error, for url: URL) {
        os_unfair_lock_lock(&lock)
        stubs[url] = .error(error)
        os_unfair_lock_unlock(&lock)
    }

    /// Stubs the given URL to return an empty body with the given status code.
    static func stub(statusCode: Int, for url: URL) {
        stub(data: Data(), statusCode: statusCode, for: url)
    }

    /// Removes all stubs and the response handler.
    static func clear() {
        os_unfair_lock_lock(&lock)
        stubs.removeAll()
        responseHandler = nil
        os_unfair_lock_unlock(&lock)
    }

    // MARK: - URLProtocol overrides

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override static func requestIsCacheEquivalent(_ a: URLRequest, to b: URLRequest) -> Bool { false }

    override func startLoading() {
        // 1. Try closure-based handler first
        if let handler = URLProtocolStub.responseHandler {
            do {
                let (data, response) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch let error as URLError {
                client?.urlProtocol(self, didFailWithError: error)
            } catch {
                client?.urlProtocol(
                    self,
                    didFailWithError: URLError(
                        .unknown,
                        userInfo: [NSLocalizedDescriptionKey: String(describing: error)]
                    )
                )
            }
            return
        }

        // 2. Fall back to stub dictionary
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        os_unfair_lock_lock(&Self.lock)
        let stub = Self.stubs[url]
        os_unfair_lock_unlock(&Self.lock)

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        switch stub {
        case let .data(data, statusCode):
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)

        case let .error(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    // MARK: - Session factory

    /// Creates an ephemeral `URLSession` that uses this protocol stub.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }
}
