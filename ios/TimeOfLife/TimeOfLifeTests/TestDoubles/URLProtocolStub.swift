import Foundation

/// URLProtocol subclass that serves canned responses for `APIClient` tests.
///
/// Configure `URLProtocolStub.responseHandler` before the request; it
/// receives the URL request and returns a `(Data, HTTPURLResponse)` tuple.
/// Throws are propagated as `URLError`.
final class URLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var responseHandler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override class func requestIsCacheEquivalent(_ a: URLRequest, to b: URLRequest) -> Bool { false }

    override func startLoading() {
        guard let handler = URLProtocolStub.responseHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch let error as URLError {
            client?.urlProtocol(self, didFailWithError: error)
        } catch {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown, userInfo: [NSLocalizedDescriptionKey: String(describing: error)]))
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self] + (config.protocolClasses ?? [])
        return URLSession(configuration: config)
    }
}