import XCTest
import Vapor
import Fluent
@testable import App

final class AuthServiceTests: XCTestCase {

    func testSignUpCreatesUnverifiedUserAndSendsVerification() async throws {
        let (app, emailer) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let auth = app.services!.auth

        let user = try await auth.signUp(email: "Alice@Example.com ", password: "Abcdef12", language: .en, on: app.db)

        // Email normalized.
        XCTAssertEqual(user.email, "alice@example.com")
        XCTAssertFalse(user.isEmailVerified)
        XCTAssertNotNil(user.createdAt)
        // Password hashed (not plaintext).
        XCTAssertNotEqual(user.passwordHash, "Abcdef12")
        XCTAssertTrue(user.passwordHash.hasPrefix("$2b$04$"))

        // Verification email captured.
        XCTAssertEqual(emailer.captured.count, 1)
        let sent = emailer.captured[0]
        XCTAssertEqual(sent.to, "alice@example.com")
        XCTAssertEqual(sent.subjectKey, .verifyEmail)
        XCTAssertEqual(sent.language, .en)
        XCTAssertTrue(sent.linkURL.hasPrefix("timeoflife://verify?token="))

        // A verification token row exists.
        let tokens = try await EmailVerificationToken.query(on: app.db).filter(\.$user.$id == user.id!).all()
        XCTAssertEqual(tokens.count, 1)
        XCTAssertFalse(tokens[0].used)
    }

    func testSignUpDuplicateEmailThrowsEmailTaken() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let auth = app.services!.auth
        _ = try await auth.signUp(email: "dup@example.com", password: "Abcdef12", language: .en, on: app.db)

        do {
            _ = try await auth.signUp(email: "DUP@example.com", password: "Abcdef12", language: .en, on: app.db)
            XCTFail("expected emailTaken")
        } catch AuthError.emailTaken {
            // expected
        }
    }

    func testSignUpWeakPasswordThrows() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let auth = app.services!.auth
        do {
            _ = try await auth.signUp(email: "weak@example.com", password: "abcdefgh", language: .en, on: app.db)
            XCTFail("expected weakPassword")
        } catch AuthError.weakPassword {
            // expected
        }
        // No user created.
        let users = try await User.query(on: app.db).filter(\.$email == "weak@example.com").all()
        XCTAssertEqual(users.count, 0)
    }

    func testRefreshRotatesAndReuseRevokesAll() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let auth = app.services!.auth
        let user = try await auth.signUp(email: "rot@example.com", password: "Abcdef12", language: .en, on: app.db)

        let raw1 = try await app.services!.tokens.issueRefreshToken(for: user.id!, on: app.db)
        let (_, raw2, _) = try await auth.refresh(rawOld: raw1, on: app.db)
        XCTAssertNotEqual(raw1, raw2)

        // Reuse old → tokenReuse.
        do {
            _ = try await auth.refresh(rawOld: raw1, on: app.db)
            XCTFail("expected tokenReuse")
        } catch AuthError.tokenReuse {
            // expected
        }

        // All tokens revoked.
        let all = try await RefreshToken.query(on: app.db).filter(\.$user.$id == user.id!).all()
        XCTAssertTrue(all.allSatisfy { $0.revoked })

        // raw2 also revoked → using it throws reuse.
        do {
            _ = try await auth.refresh(rawOld: raw2, on: app.db)
            XCTFail("expected tokenReuse for raw2")
        } catch AuthError.tokenReuse {
            // expected
        }
    }

    func testLogoutRevokesToken() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let auth = app.services!.auth
        let user = try await auth.signUp(email: "out@example.com", password: "Abcdef12", language: .en, on: app.db)
        let raw = try await app.services!.tokens.issueRefreshToken(for: user.id!, on: app.db)

        try await auth.logout(raw: raw, on: app.db)

        let record = try await RefreshToken.query(on: app.db).filter(\.$tokenHash == TokenService.sha256Hex(raw)).first()
        XCTAssertTrue(record?.revoked == true)
    }

    func testNormalizeEmail() throws {
        XCTAssertEqual(try AuthService.normalizeEmail("  Alice@Example.com "), "alice@example.com")
        XCTAssertThrowsError(try AuthService.normalizeEmail(""))
        // Too long.
        let long = String(repeating: "a", count: 250) + "@b.co"
        XCTAssertThrowsError(try AuthService.normalizeEmail(long))
        // Malformed.
        XCTAssertThrowsError(try AuthService.normalizeEmail("noatsign"))
    }
}