import Foundation
@testable import TimeOfLife

/// Records calls and returns canned results / errors. Used to drive
/// `AuthService` and view models without a network.
final class FakeAuthRepository: AuthRepository, @unchecked Sendable {
    enum Call: Equatable {
        case signup(email: String, password: String)
        case verifyEmail(token: String)
        case resendVerification(email: String)
        case signin(email: String, password: String)
        case refresh(refreshToken: String)
        case logout
        case me
        case requestPasswordReset(email: String)
        case confirmPasswordReset(token: String, newPassword: String)
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }

    // Canned results.
    var signupResult: SignupResponse = .init(user: UserDTO(id: "u1", email: "a@b.com", emailVerified: false))
    var verifyResult: AuthSession = .init(accessToken: "at", refreshToken: "rt", user: UserDTO(id: "u1", email: "a@b.com", emailVerified: true))
    var signinResult: AuthSession = .init(accessToken: "at", refreshToken: "rt", user: UserDTO(id: "u1", email: "a@b.com", emailVerified: true))
    var refreshResult: AuthSession = .init(accessToken: "at2", refreshToken: "rt2", user: UserDTO(id: "u1", email: "a@b.com", emailVerified: true))
    var meResult: UserDTO = .init(id: "u1", email: "a@b.com", emailVerified: true)

    // Per-method errors to throw (overrides result).
    var signupError: Error?
    var verifyError: Error?
    var resendError: Error?
    var signinError: Error?
    var refreshError: Error?
    var logoutError: Error?
    var meError: Error?
    var resetRequestError: Error?
    var resetConfirmError: Error?

    func record(_ call: Call) { lock.lock(); _calls.append(call); lock.unlock() }

    func signup(email: String, password: String) async throws -> SignupResponse {
        record(.signup(email: email, password: password))
        if let e = signupError { throw e }
        return signupResult
    }
    func verifyEmail(token: String) async throws -> AuthSession {
        record(.verifyEmail(token: token))
        if let e = verifyError { throw e }
        return verifyResult
    }
    func resendVerification(email: String) async throws {
        record(.resendVerification(email: email))
        if let e = resendError { throw e }
    }
    func signin(email: String, password: String) async throws -> AuthSession {
        record(.signin(email: email, password: password))
        if let e = signinError { throw e }
        return signinResult
    }
    func refresh(refreshToken: String) async throws -> AuthSession {
        record(.refresh(refreshToken: refreshToken))
        if let e = refreshError { throw e }
        return refreshResult
    }
    func logout() async throws {
        record(.logout)
        if let e = logoutError { throw e }
    }
    func me() async throws -> UserDTO {
        record(.me)
        if let e = meError { throw e }
        return meResult
    }
    func requestPasswordReset(email: String) async throws {
        record(.requestPasswordReset(email: email))
        if let e = resetRequestError { throw e }
    }
    func confirmPasswordReset(token: String, newPassword: String) async throws {
        record(.confirmPasswordReset(token: token, newPassword: newPassword))
        if let e = resetConfirmError { throw e }
    }
}