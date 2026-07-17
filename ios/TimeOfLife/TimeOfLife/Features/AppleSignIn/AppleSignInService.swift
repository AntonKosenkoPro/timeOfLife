import Foundation

// DEFERRED: F2 — Sign in with Apple. No-op until implemented.
enum AppleSignInError: Error {
    case notImplemented
}

/// Stub service. Throwing `notImplemented` keeps the call site real while the
/// feature is gated behind the disabled button.
final class AppleSignInService: Sendable {
    init() {}

    func signIn() async throws -> AuthSession {
        // DEFERRED: F2
        throw AppleSignInError.notImplemented
    }
}