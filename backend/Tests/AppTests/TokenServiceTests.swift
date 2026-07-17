import XCTest
import Vapor
import Fluent
@testable import App

final class TokenServiceTests: XCTestCase {

    private func makeUser(on db: Database, email: String = "alice@example.com") async throws -> User {
        let user = User(email: email, passwordHash: "$2b$04$abcdabcdabcdabcdabcdabuVQXqXqXqXqXqXqXqXqXqXqXqXqXq")
        try await user.save(on: db)
        return user
    }

    func testIssueAndVerifyAccessToken() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let tokens = app.services!.tokens
        let user = try await makeUser(on: app.db)

        let jwt = try await tokens.issueAccessToken(user: user)
        XCTAssertFalse(jwt.isEmpty)

        let claims = try await tokens.verifyAccessToken(jwt)
        XCTAssertEqual(claims.sub.value, user.id!.uuidString)
        XCTAssertEqual(claims.email, user.email)
    }

    func testVerifyRejectsTamperedToken() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let tokens = app.services!.tokens
        let user = try await makeUser(on: app.db)
        let jwt = try await tokens.issueAccessToken(user: user)
        let tampered = String(jwt.dropLast()) + "Z"
        do {
            _ = try await tokens.verifyAccessToken(tampered)
            XCTFail("expected verification failure")
        } catch {
            // expected
        }
    }

    func testIssueRefreshPersistsHashOnly() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let tokens = app.services!.tokens
        let user = try await makeUser(on: app.db)

        let raw = try await tokens.issueRefreshToken(for: user.id!, on: app.db)
        XCTAssertFalse(raw.isEmpty)

        let stored = try await RefreshToken.query(on: app.db).filter(\.$user.$id == user.id!).all()
        XCTAssertEqual(stored.count, 1)
        XCTAssertNotEqual(stored[0].tokenHash, raw)           // hash not raw
        XCTAssertEqual(stored[0].tokenHash, TokenService.sha256Hex(raw))
        XCTAssertFalse(stored[0].revoked)
    }

    func testRotateIssuesNewPairAndRevokesOld() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let tokens = app.services!.tokens
        let user = try await makeUser(on: app.db)

        let raw1 = try await tokens.issueRefreshToken(for: user.id!, on: app.db)
        let (access, raw2, returnedUser) = try await tokens.rotateRefreshToken(rawOld: raw1, on: app.db)
        XCTAssertFalse(access.isEmpty)
        XCTAssertFalse(raw2.isEmpty)
        XCTAssertNotEqual(raw1, raw2)
        XCTAssertEqual(returnedUser.id, user.id)

        // Old token revoked; new one active.
        let all = try await RefreshToken.query(on: app.db).filter(\.$user.$id == user.id!).all()
        XCTAssertEqual(all.count, 2)
        let oldRecord = all.first(where: { $0.tokenHash == TokenService.sha256Hex(raw1) })!
        XCTAssertTrue(oldRecord.revoked)
        let newRecord = all.first(where: { $0.tokenHash == TokenService.sha256Hex(raw2) })!
        XCTAssertFalse(newRecord.revoked)
    }

    func testReuseOfRevokedRevokesAllAndThrowsTokenReuse() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let tokens = app.services!.tokens
        let user = try await makeUser(on: app.db)

        let raw1 = try await tokens.issueRefreshToken(for: user.id!, on: app.db)
        let raw2 = try await tokens.issueRefreshToken(for: user.id!, on: app.db)

        // Rotate raw1 (revokes raw1, issues raw3).
        _ = try await tokens.rotateRefreshToken(rawOld: raw1, on: app.db)

        // Reuse raw1 again → tokenReuse + all revoked.
        do {
            _ = try await tokens.rotateRefreshToken(rawOld: raw1, on: app.db)
            XCTFail("expected tokenReuse")
        } catch AuthError.tokenReuse {
            // expected
        }

        let all = try await RefreshToken.query(on: app.db).filter(\.$user.$id == user.id!).all()
        for r in all { XCTAssertTrue(r.revoked, "token \(r.tokenHash) should be revoked") }

        // raw2 is now revoked too — using it should also trigger reuse (all already revoked).
        do {
            _ = try await tokens.rotateRefreshToken(rawOld: raw2, on: app.db)
            XCTFail("expected tokenReuse for raw2")
        } catch AuthError.tokenReuse {
            // expected
        }
    }

    func testExpiredTokenThrowsExpired() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let config = app.services!.config
        // Build a token service with TTL = 0 so it expires immediately.
        let expiredConfig = AppConfig(
            databaseURL: config.databaseURL, jwtSecret: config.jwtSecret,
            jwtIssuer: config.jwtIssuer, accessTokenTTLSeconds: 900,
            refreshTokenTTLSeconds: 0, bcryptCost: 4, emailBackend: .console,
            mailgun: nil, resetLinkBase: config.resetLinkBase, verifyLinkBase: config.verifyLinkBase
        )
        let tokens = TokenService(app: app, config: expiredConfig)
        let user = try await makeUser(on: app.db)

        let raw = try await tokens.issueRefreshToken(for: user.id!, on: app.db)
        // expiry = now → immediately expired.
        do {
            _ = try await tokens.rotateRefreshToken(rawOld: raw, on: app.db)
            XCTFail("expected tokenExpired")
        } catch AuthError.tokenExpired {
            // expected
        }
    }

    func testInvalidRefreshThrows() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let tokens = app.services!.tokens
        do {
            _ = try await tokens.rotateRefreshToken(rawOld: "nonexistent", on: app.db)
            XCTFail("expected invalidRefresh")
        } catch AuthError.invalidRefresh {
            // expected
        }
    }

    func testRevokeAllForUser() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let tokens = app.services!.tokens
        let user = try await makeUser(on: app.db)
        _ = try await tokens.issueRefreshToken(for: user.id!, on: app.db)
        _ = try await tokens.issueRefreshToken(for: user.id!, on: app.db)
        _ = try await tokens.issueRefreshToken(for: user.id!, on: app.db)

        try await tokens.revokeAllForUser(user.id!, on: app.db)
        let all = try await RefreshToken.query(on: app.db).filter(\.$user.$id == user.id!).all()
        XCTAssertTrue(all.allSatisfy { $0.revoked })
    }
}