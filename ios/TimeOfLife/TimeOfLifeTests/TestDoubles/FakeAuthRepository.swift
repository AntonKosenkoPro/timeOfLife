import Foundation
@testable import TimeOfLife

/// Records calls and returns canned results / errors. Used to drive
/// `AuthService` and view models without a network.
///
/// Thread-safe via `NSLock`.
final class FakeAuthRepository: AuthRepository, @unchecked Sendable {

    /// Recorded call types for verification.
    enum Call: Equatable {
        case requestOtp(email: String)
        case verifyOtp(email: String, code: String)
        case appleSignIn(identityToken: String)
        case refresh(refreshToken: String)
        case logout
        case me
    }

    // MARK: - State

    private let lock = NSLock()
    private var _calls: [Call] = []

    /// All recorded calls, in order.
    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    // MARK: - Canned results

    /// Result returned by `verifyOtp` when no error is set.
    var otpVerifyResult = AuthSession(
        accessToken: "at",
        refreshToken: "rt",
        user: UserDTO(id: "u1", email: "a@b.com", emailVerified: true)
    )

    /// Result returned by `appleSignIn` when no error is set.
    var appleSignInResult = AuthSession(
        accessToken: "at-apple",
        refreshToken: "rt-apple",
        user: UserDTO(id: "u-apple", email: "apple@privaterelay.appleid.com", emailVerified: true)
    )

    /// Result returned by `refresh` when no error is set.
    var refreshResult = AuthSession(
        accessToken: "at2",
        refreshToken: "rt2",
        user: UserDTO(id: "u1", email: "a@b.com", emailVerified: true)
    )

    /// Result returned by `me` when no error is set.
    var meResult = UserDTO(id: "u1", email: "a@b.com", emailVerified: true)

    // MARK: - Per-method errors

    /// If set, `requestOtp` throws this error.
    var otpRequestError: Error?
    /// If set, `verifyOtp` throws this error.
    var otpVerifyError: Error?
    /// If set, `appleSignIn` throws this error.
    var appleSignInError: Error?
    /// If set, `refresh` throws this error.
    var refreshError: Error?
    /// If set, `logout` throws this error.
    var logoutError: Error?
    /// If set, `me` throws this error.
    var meError: Error?

    // MARK: - Recording

    func record(_ call: Call) {
        lock.lock(); _calls.append(call); lock.unlock()
    }

    // MARK: - Refresh gate (single-flight testing)

    private let gateLock = NSLock()
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []

    /// When true, `refresh` records its call then suspends until
    /// `releaseRefreshGate()` is called. Used to test that concurrent
    /// `performRefresh` calls coalesce into a single network refresh.
    var refreshGateHeld = false

    /// Resumes every `refresh` call suspended on the gate.
    func releaseRefreshGate() {
        gateLock.lock()
        let waiters = refreshWaiters
        refreshWaiters.removeAll()
        gateLock.unlock()
        for w in waiters { w.resume(returning: ()) }
    }

    // MARK: - AuthRepository

    func requestOtp(email: String) async throws {
        record(.requestOtp(email: email))
        if let e = otpRequestError { throw e }
    }

    func verifyOtp(email: String, code: String) async throws -> AuthSession {
        record(.verifyOtp(email: email, code: code))
        if let e = otpVerifyError { throw e }
        return AuthSession(
            accessToken: otpVerifyResult.accessToken,
            refreshToken: otpVerifyResult.refreshToken,
            user: UserDTO(
                id: otpVerifyResult.user.id,
                email: email,
                emailVerified: otpVerifyResult.user.emailVerified
            )
        )
    }

    func appleSignIn(identityToken: String) async throws -> AuthSession {
        record(.appleSignIn(identityToken: identityToken))
        if let e = appleSignInError { throw e }
        return appleSignInResult
    }

    func refresh(refreshToken: String) async throws -> AuthSession {
        record(.refresh(refreshToken: refreshToken))
        if refreshGateHeld {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                gateLock.lock()
                refreshWaiters.append(cont)
                gateLock.unlock()
            }
        }
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

    /// Resets all recorded calls and errors.
    func reset() {
        lock.lock()
        _calls.removeAll()
        otpRequestError = nil
        otpVerifyError = nil
        appleSignInError = nil
        refreshError = nil
        logoutError = nil
        meError = nil
        lock.unlock()
    }
}
