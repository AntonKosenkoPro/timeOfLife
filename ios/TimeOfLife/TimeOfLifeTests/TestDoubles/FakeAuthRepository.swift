import Foundation
@testable import TimeOfLife

/// Records calls and returns canned results / errors. Used to drive
/// `AuthService` and view models without a network.
final class FakeAuthRepository: AuthRepository, @unchecked Sendable {
    enum Call: Equatable {
        case requestOtp(email: String)
        case verifyOtp(email: String, code: String)
        case refresh(refreshToken: String)
        case logout
        case me
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    var calls: [Call] { lock.lock(); defer { lock.unlock() }; return _calls }

    // Canned results.
    var otpVerifyResult: AuthSession = .init(accessToken: "at", refreshToken: "rt",
                                              user: UserDTO(id: "u1", email: "a@b.com", emailVerified: true))
    var refreshResult: AuthSession = .init(accessToken: "at2", refreshToken: "rt2",
                                           user: UserDTO(id: "u1", email: "a@b.com", emailVerified: true))
    var meResult: UserDTO = .init(id: "u1", email: "a@b.com", emailVerified: true)

    // Per-method errors to throw (overrides result).
    var otpRequestError: Error?
    var otpVerifyError: Error?
    var refreshError: Error?
    var logoutError: Error?
    var meError: Error?

    func record(_ call: Call) { lock.lock(); _calls.append(call); lock.unlock() }

    func requestOtp(email: String) async throws {
        record(.requestOtp(email: email))
        if let e = otpRequestError { throw e }
    }
    func verifyOtp(email: String, code: String) async throws -> AuthSession {
        record(.verifyOtp(email: email, code: code))
        if let e = otpVerifyError { throw e }
        return otpVerifyResult
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
}