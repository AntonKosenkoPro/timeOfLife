import XCTest
import Vapor
import Fluent
@testable import App

final class EmailVerificationServiceTests: XCTestCase {

    private func makeVerifiedFlow() async throws -> (Application, CapturingEmailSender, User, String) {
        let (app, emailer) = try await TestApp.make()
        let user = try await app.services!.auth.signUp(email: "verify@example.com", password: "Abcdef12", language: .ru, on: app.db)
        let raw = emailer.rawToken(at: 0)!
        return (app, emailer, user, raw)
    }

    func testVerifyMarksUserVerifiedAndIssuesTokens() async throws {
        let (app, _, user, raw) = try await makeVerifiedFlow()
        addTeardownBlock { try await app.asyncShutdown() }
        let emails = app.services!.emails

        let (verified, access, refresh) = try await emails.verify(rawToken: raw, on: app.db)
        XCTAssertEqual(verified.id, user.id)
        XCTAssertTrue(verified.isEmailVerified)
        XCTAssertFalse(access.isEmpty)
        XCTAssertFalse(refresh.isEmpty)

        // Token marked used.
        let record = try await EmailVerificationToken.query(on: app.db)
            .filter(\.$tokenHash == TokenService.sha256Hex(raw)).first()
        XCTAssertTrue(record?.used == true)

        // User persisted as verified.
        let dbUser = try await User.find(user.id, on: app.db)
        XCTAssertNotNil(dbUser?.emailVerifiedAt)
    }

    func testVerifyInvalidToken() async throws {
        let (app, _, _, _) = try await makeVerifiedFlow()
        addTeardownBlock { try await app.asyncShutdown() }
        do {
            _ = try await app.services!.emails.verify(rawToken: "not-a-real-token", on: app.db)
            XCTFail("expected tokenInvalid")
        } catch VerifyError.tokenInvalid {
            // expected
        }
    }

    func testVerifyUsedTokenThrowsUsed() async throws {
        let (app, _, _, raw) = try await makeVerifiedFlow()
        addTeardownBlock { try await app.asyncShutdown() }
        _ = try await app.services!.emails.verify(rawToken: raw, on: app.db)
        do {
            _ = try await app.services!.emails.verify(rawToken: raw, on: app.db)
            XCTFail("expected tokenUsed")
        } catch VerifyError.tokenUsed {
            // expected
        }
    }

    func testVerifyExpiredTokenThrowsExpired() async throws {
        let (app, _, user, _) = try await makeVerifiedFlow()
        addTeardownBlock { try await app.asyncShutdown() }
        // Insert an already-expired token.
        let raw = TokenService.generateOpaqueToken()
        let record = EmailVerificationToken(
            userID: user.id!,
            tokenHash: TokenService.sha256Hex(raw),
            expiresAt: Date().addingTimeInterval(-60),
            used: false
        )
        try await record.create(on: app.db)

        do {
            _ = try await app.services!.emails.verify(rawToken: raw, on: app.db)
            XCTFail("expected tokenExpired")
        } catch VerifyError.tokenExpired {
            // expected
        }
    }

    func testResendSendsToUnverifiedUser() async throws {
        let (app, emailer) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        _ = try await app.services!.auth.signUp(email: "resend@example.com", password: "Abcdef12", language: .en, on: app.db)
        emailer.reset()

        let sent = try await app.services!.emails.resend(email: "resend@example.com", language: .en, on: app.db)
        XCTAssertTrue(sent)
        XCTAssertEqual(emailer.captured.count, 1)
    }

    func testResendNoOpForUnknownEmail() async throws {
        let (app, emailer) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let sent = try await app.services!.emails.resend(email: "ghost@example.com", language: .en, on: app.db)
        XCTAssertFalse(sent)
        XCTAssertEqual(emailer.captured.count, 0)
    }

    func testResendNoOpForVerifiedUser() async throws {
        let (app, emailer) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        let user = try await app.services!.auth.signUp(email: "done@example.com", password: "Abcdef12", language: .en, on: app.db)
        let raw = emailer.rawToken(at: 0)!
        _ = try await app.services!.emails.verify(rawToken: raw, on: app.db)
        emailer.reset()

        let sent = try await app.services!.emails.resend(email: user.email, language: .en, on: app.db)
        XCTAssertFalse(sent)
        XCTAssertEqual(emailer.captured.count, 0)
    }
}