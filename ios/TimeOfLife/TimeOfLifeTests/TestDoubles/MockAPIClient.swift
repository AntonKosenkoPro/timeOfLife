import Foundation
@testable import TimeOfLife

/// Records endpoints and returns canned decoded results / errors. Conforms
/// to `APISending` so `RemoteAuthRepository` can be tested without a network.
final class MockAPIClient: APISending, @unchecked Sendable {
    struct Received: Equatable {
        let method: HTTPMethod
        let path: String
        let requiresAuth: Bool
        let body: Data?
    }

    private let lock = NSLock()
    private var _received: [Received] = []
    var received: [Received] { lock.lock(); defer { lock.unlock() }; return _received }

    // Canned handlers. Set these per test.
    var sendHandler: ((Any.Type, APIEndpoint) throws -> Any)?
    var sendVoidHandler: ((APIEndpoint) throws -> Void)?

    private func record(_ endpoint: APIEndpoint) {
        record(Received(method: endpoint.method, path: endpoint.path,
                        requiresAuth: endpoint.requiresAuth, body: endpoint.body))
    }
    private func record(_ r: Received) { lock.lock(); _received.append(r); lock.unlock() }

    func send<T: Decodable & Sendable>(_ endpoint: APIEndpoint, as: T.Type) async throws -> T {
        record(endpoint)
        do {
            guard let result = try sendHandler?(T.self, endpoint) as? T else {
                throw APIError.unexpected
            }
            return result
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(underlying: String(describing: error))
        }
    }

    func sendVoid(_ endpoint: APIEndpoint) async throws {
        record(endpoint)
        do {
            try sendVoidHandler?(endpoint)
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(underlying: String(describing: error))
        }
    }
}