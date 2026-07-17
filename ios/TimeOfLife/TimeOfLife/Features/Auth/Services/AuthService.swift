import Foundation
import Combine

/// Orchestrates `AuthRepository` + `KeychainStoring` + `SessionCache` +
/// `SessionStore`. Owns the token lifecycle: writes Keychain + cache on
/// sign-in/verify, rotates on refresh, clears all on logout.
///
/// `restoreSession()`: reads Keychain+cache, attempts `/me` in background;
/// on transient offline failure keeps the cached session (no logout on
/// offline). Logout works offline — clears local, best-effort server revoke.
@MainActor
final class AuthService: ObservableObject {
    let repository: AuthRepository
    let keychain: KeychainStoring
    let cache: SessionCache
    let sessionStore: SessionStore

    init(
        repository: AuthRepository,
        keychain: KeychainStoring,
        cache: SessionCache,
        sessionStore: SessionStore
    ) {
        self.repository = repository
        self.keychain = keychain
        self.cache = cache
        self.sessionStore = sessionStore
    }

    // MARK: - Public API (called by ViewModels / RootView)

    func signUp(email: String, password: String) async throws {
        let normalized = AuthValidator.normalize(email: email)
        _ = try await repository.signup(email: normalized, password: password)
        // No tokens returned on signup; user must verify email. Cache email so
        // the verify screen can pre-fill and resend knows where to send.
        sessionStore.setCachedEmail(normalized)
    }

    func verifyEmail(token: String) async throws {
        let session = try await repository.verifyEmail(token: token)
        await persist(session: session)
    }

    func resendVerification(email: String) async throws {
        try await repository.resendVerification(email: AuthValidator.normalize(email: email))
    }

    func signIn(email: String, password: String) async throws {
        let normalized = AuthValidator.normalize(email: email)
        let session = try await repository.signin(email: normalized, password: password)
        await persist(session: session)
    }

    func requestPasswordReset(email: String) async throws {
        try await repository.requestPasswordReset(email: AuthValidator.normalize(email: email))
    }

    func confirmPasswordReset(token: String, newPassword: String) async throws {
        try await repository.confirmPasswordReset(token: token, newPassword: newPassword)
    }

    /// Reads Keychain + cache; if a refresh token exists, attempts `/me`.
    /// On transient offline failure keeps the cached session.
    func restoreSession() async {
        let cached = cache.load()
        let refreshToken = await keychain.string(for: .refreshToken)
        let accessToken = await keychain.string(for: .accessToken)

        // If we have a cached session and tokens, optimistically show signed-in.
        if let cached, refreshToken != nil {
            sessionStore.setSignedIn(cached)
        }

        guard refreshToken != nil else { return }

        // Validate against the server. On failure:
        // - offline → keep cached session.
        // - 401 → try refresh; if that fails, sign out.
        do {
            let user = try await repository.me()
            let updated = CachedSession(id: user.id, email: user.email,
                                         emailVerified: user.emailVerified)
            cache.save(updated)
            sessionStore.setSignedIn(updated)
        } catch APIError.unauthorized {
            // Try to refresh.
            do {
                if let refresh = await keychain.string(for: .refreshToken) {
                    let session = try await repository.refresh(refreshToken: refresh)
                    await persist(session: session)
                } else {
                    await clearLocal()
                }
            } catch {
                await clearLocal()
            }
        } catch APIError.offline {
            // Keep cached session; do not log out on offline (U3).
        } catch {
            // Any other server error: don't trust the session.
            await clearLocal()
        }
        _ = accessToken // referenced for clarity
    }

    /// Refresh helper exposed for `APIClient`'s refresh hook. Rotates tokens
    /// and persists the new pair. Returns the new access token.
    func performRefresh() async throws -> String {
        guard let refresh = await keychain.string(for: .refreshToken) else {
            throw APIError.unauthorized
        }
        let session = try await repository.refresh(refreshToken: refresh)
        await persist(session: session)
        return session.accessToken
    }

    /// Logout. Clears local state always; best-effort server revoke.
    func logout() async {
        do {
            try await repository.logout()
        } catch {
            // Best-effort: ignore network/401 — we still clear local state.
        }
        await clearLocal()
    }

    // MARK: - Internals

    private func persist(session: AuthSession) async {
        await keychain.setString(session.accessToken, for: .accessToken)
        await keychain.setString(session.refreshToken, for: .refreshToken)
        let cached = CachedSession(id: session.user.id, email: session.user.email,
                                   emailVerified: session.user.emailVerified)
        cache.save(cached)
        sessionStore.setSignedIn(cached)
    }

    private func clearLocal() async {
        await keychain.remove(key: .accessToken)
        await keychain.remove(key: .refreshToken)
        cache.clear()
        sessionStore.setSignedOut()
    }
}