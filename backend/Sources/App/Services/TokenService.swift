import Foundation
import Fluent
import Vapor
import JWTKit
import JWT
import Crypto

/// JWT access-token payload (HS256).
struct AccessTokenClaims: JWTPayload, Equatable {
    let sub: SubjectClaim
    let email: String
    let iat: IssuedAtClaim
    let exp: ExpirationClaim

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try exp.verifyNotExpired()
    }
}

/// Issues JWT access tokens + opaque, rotated refresh tokens with reuse detection.
final class TokenService: Sendable {
    let app: Application
    let config: AppConfig

    init(app: Application, config: AppConfig) {
        self.app = app
        self.config = config
    }

    // MARK: Access token

    func issueAccessToken(user: User) async throws -> String {
        let now = Date()
        let exp = now.addingTimeInterval(TimeInterval(config.accessTokenTTLSeconds))
        let claims = AccessTokenClaims(
            sub: .init(value: user.id!.uuidString),
            email: user.email,
            iat: .init(value: now),
            exp: .init(value: exp)
        )
        return try await app.jwt.keys.sign(claims)
    }

    func verifyAccessToken(_ token: String) async throws -> AccessTokenClaims {
        try await app.jwt.keys.verify(token, as: AccessTokenClaims.self)
    }

    // MARK: Refresh token

    /// Generate a 32-byte opaque token (hex-encoded). The raw value is returned once;
    /// only its SHA-256 hash is persisted.
    static func generateOpaqueToken() -> String {
        var rng = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: 32)
        for i in 0..<bytes.count {
            bytes[i] = UInt8.random(in: 0...255, using: &rng)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256Hex(_ raw: String) -> String {
        let data = Data(raw.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Persist a new refresh token for `userID`. Returns the raw token (returned to client once).
    func issueRefreshToken(
        for userID: UUID,
        deviceId: String? = nil,
        userAgent: String? = nil,
        on db: Database
    ) async throws -> String {
        let raw = Self.generateOpaqueToken()
        let hash = Self.sha256Hex(raw)
        let expiresAt = Date().addingTimeInterval(TimeInterval(config.refreshTokenTTLSeconds))
        let record = RefreshToken(
            userID: userID,
            tokenHash: hash,
            deviceId: deviceId,
            userAgent: userAgent,
            expiresAt: expiresAt,
            revoked: false
        )
        try await record.create(on: db)
        return raw
    }

    /// Rotate a refresh token: revoke the old one and issue a fresh pair.
    /// Detects reuse of a revoked token → revokes ALL the user's tokens and throws `token_reuse`.
    func rotateRefreshToken(
        rawOld: String,
        on db: Database
    ) async throws -> (access: String, refresh: String, user: User) {
        let hash = Self.sha256Hex(rawOld)
        guard let record = try await RefreshToken.query(on: db)
            .filter(\.$tokenHash == hash)
            .first()
        else {
            throw AuthError.invalidRefresh
        }

        // Reuse detection: a revoked token being presented again → burn everything.
        if record.revoked {
            try await revokeAllForUser(record.$user.id, on: db)
            throw AuthError.tokenReuse
        }

        // Expired → revoke and reject (not reuse).
        if record.expiresAt <= Date() {
            record.revoked = true
            try await record.save(on: db)
            throw AuthError.tokenExpired
        }

        // Rotate: revoke current, issue new.
        record.revoked = true
        try await record.save(on: db)

        guard let user = try await User.find(record.$user.id, on: db) else {
            throw AuthError.invalidRefresh
        }

        let access = try await issueAccessToken(user: user)
        let refresh = try await issueRefreshToken(
            for: user.id!,
            deviceId: record.deviceId,
            userAgent: record.userAgent,
            on: db
        )
        return (access, refresh, user)
    }

    /// Revoke a single refresh token (logout). Throws `invalid_refresh` if not found.
    func revokeRefreshToken(raw: String, on db: Database) async throws {
        let hash = Self.sha256Hex(raw)
        guard let record = try await RefreshToken.query(on: db)
            .filter(\.$tokenHash == hash)
            .first()
        else {
            // Logout is idempotent-ish; missing token still 204 per API table? We throw for 401 path.
            throw AuthError.invalidRefresh
        }
        if !record.revoked {
            record.revoked = true
            try await record.save(on: db)
        }
    }

    /// Revoke every refresh token belonging to `userID`. Called on password change + reuse.
    func revokeAllForUser(_ userID: UUID, on db: Database) async throws {
        let records = try await RefreshToken.query(on: db)
            .filter(\.$user.$id == userID)
            .all()
        for record in records where !record.revoked {
            record.revoked = true
            try await record.save(on: db)
        }
    }
}