import Foundation

/// Abstraction over the network client so `RemoteAuthRepository` can be tested
/// with a mock and production can use `APIClient`.
protocol APISending: Sendable {
    func send<T: Decodable & Sendable>(_ endpoint: APIEndpoint, as: T.Type) async throws -> T
    func sendVoid(_ endpoint: APIEndpoint) async throws
}