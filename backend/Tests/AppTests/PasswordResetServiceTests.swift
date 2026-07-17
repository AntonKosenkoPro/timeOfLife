import XCTest
import Vapor
import Fluent
@testable import App

final class PasswordResetServiceTests: XCTestCase {

    func testRequestResetSendsEmailAndInvalidatesPriorTokens() async throws {
        let (app, emailer) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let svc = app.services!.passwordReset
        _ = try await app.services!.auth.signUp(email: "reset@example.com", password: "Abcdef12", language: .en, on: app.db)
        // Verify the user so the account is "real".
        let verifyRaw = emailer.rawToken(at: 0)!
        _ = try await app.services!.emails.verify(rawToken: verifyRaw, on: app.db)

        let sent1 = try await svc.requestReset(email: "reset@example.com", language: .en, on: app.db)
        XCTAssertTrue(sent1)
        let firstRaw = emailer.captured.first(where: { $0.subjectKey == .passwordReset })!.linkURL
            .split(separator: "=").last.map(String.init)!

        let sent2 = try await svc.requestReset(email: "reset@example.com", language: .ru, on: app.db)
        XCTAssertTrue(sent2)

        // First token now used (invalidated).
        let firstRecord = try await PasswordResetToken.query(on: app.db)
            .filter(\.$tokenHash == TokenService.sha256Hex(firstRaw)).first()
        XCTAssertTrue(firstRecord?.used == true)

        // Two reset emails captured (EN + RU).
        let resetEmails = emailer.captured.filter { $0.subjectKey == .passwordReset }
        XCTAssertEqual(resetEmails.count, 2)
    }

    func testRequestResetNoOpForUnknownEmail() async throws {
        let (app, emailer) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let sent = try await app.services!.passwordReset.requestReset(email: "ghost@example.com", language: .en, on: app.db)
        XCTAssertFalse(sent)
        XCTAssertEqual(emailer.captured.count, 0)
    }

    func testConfirmResetUpdatesPasswordAndRevokesSessions() async throws {
        let (app, emailer) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let svc = app.services!.passwordReset
        let user = try await app.services!.auth.signUp(email: "confirm@example.com", password: "Abcdef12", language: .en, on: app.db)
        let verifyRaw = emailer.rawToken(at: 0)!
        _ = try await app.services!.emails.verify(rawToken: verifyRaw, on: app.db)

        // Issue a refresh token (session) that should be revoked on reset.
        let refresh = try await app.services!.tokens.issueRefreshToken(for: user.id!, on: app.db)

        _ = try await svc.requestReset(email: "confirm@example.com", language: .en, on: app.db)
        let resetRaw = emailer.captured.first(where: { $0.subjectKey == .passwordReset })!.linkURL
            .split(separator: "=").last.map(String.init)!

        try await svc.confirmReset(rawToken: resetRaw, newPassword: "NewPass12", on: app.db)

        // Password changed.
        let updated = try await User.find(user.id, on: app.db)
        XCTAssertNotEqual(updated?.passwordHash, user.passwordHash)
        XCTAssertTrue(updated?.passwordHash.hasPrefix("$2b$04$") == true)

        // Can now sign in with the new password.
        let dbUser = try await User.query(on: app.db).filter(\.$email == "confirm@example.com").first()!
        XCTAssertTrue(try Bcrypt.verify("NewPass12", created: dbUser.passwordHash))

        // Refresh token revoked.
        let record = try await RefreshToken.query(on: app.db)
            .filter(\.$tokenHash == TokenService.sha256Hex(refresh)).first()
        XCTAssertTrue(record?.revoked == true)

        // Reset token marked used.
        let resetRecord = try await PasswordResetToken.query(on: app.db)
            .filter(\.$tokenHash == TokenService.sha256Hex(resetRaw)).first()
        XCTAssertTrue(resetRecord?.used == true)
    }

    func testConfirmResetInvalidToken() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        do {
            try await app.services!.passwordReset.confirmReset(rawToken: "nope", newPassword: "NewPass12", on: app.db)
            XCTFail("expected tokenInvalid")
        } catch ResetError.tokenInvalid {
            // expected
        }
    }

    func testConfirmResetUsedToken() async throws {
        let (app, emailer) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let svc = app.services!.passwordReset
        _ = try await app.services!.auth.signUp(email: "used@example.com", password: "Abcdef12", language: .en, on: app.db)
        let verifyRaw = emailer.rawToken(at: 0)!
        _ = try await app.services!.emails.verify(rawToken: verifyRaw, on: app.db)
        _ = try await svc.requestReset(email: "used@example.com", language: .en, on: app.db)
        let raw = emailer.captured.first(where: { $0.subjectKey == .passwordReset })!.linkURL
            .split(separator: "=").last.map(String.init)!

        try await svc.confirmReset(rawToken: raw, newPassword: "NewPass12", on: app.db)
        do {
            try await svc.confirmReset(rawToken: raw, newPassword: "Another12", on: app.db)
            XCTFail("expected tokenUsed")
        } catch ResetError.tokenUsed {
            // expected
        }
    }

    func testConfirmResetExpiredToken() async throws {
        let (app, emailer) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let svc = app.services!.passwordReset
        let user = try await app.services!.auth.signUp(email: "exp@example.com", password: "Abcdef12", language: .en, on: app.db)
        let verifyRaw = emailer.rawToken(at: 0)!
        _ = try await app.services!.emails.verify(rawToken: verifyRaw, on: app.db)

        // Insert expired reset token.
        let raw = TokenService.generateOpaqueToken()
        let record = PasswordResetToken(
            userID: user.id!,
            tokenHash: TokenService.sha256Hex(raw),
            expiresAt: Date().addingTimeInterval(-60),
            used: false
        )
        try await record.create(on: app.db)

        do {
            try await svc.confirmReset(rawToken: raw, newPassword: "NewPass12", on: app.db)
            XCTFail("expected tokenExpired")
        } catch ResetError.tokenExpired {
            // expected
        }
    }

    func testConfirmResetWeakPassword() async throws {
        let (app, emailer) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let svc = app.services!.passwordReset
        let user = try await app.services!.auth.signUp(email: "weak@example.com", password: "Abcdef12", language: .en, on: app.db)
        let verifyRaw = emailer.rawToken(at: 0)!
        _ = try await app.services!.emails.verify(rawToken: verifyRaw, on: app.db)
        _ = try await svc.requestReset(email: "weak@example.com", language: .en, on: app.db)
        let raw = emailer.captured.first(where: { $0.subjectKey == .passwordReset })!.linkURL
            .split(separator: "=").last.map(String.init)!

        do {
            try await svc.confirmReset(rawToken: raw, newPassword: "allletters", on: app.db)
            XCTFail("expected weakPassword")
        } catch ResetError.weakPassword {
            // expected
        }
        // Password unchanged.
        let dbUser = try await User.find(user.id, on: app.db)
        XCTAssertEqual(dbUser?.passwordHash, user.passwordHash)
    }
}