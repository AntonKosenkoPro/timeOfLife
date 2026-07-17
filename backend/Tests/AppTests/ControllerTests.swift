import XCTest
import Vapor
import XCTVapor
@testable import App

final class ControllerTests: XCTestCase {

    private struct BlankBody: Content {}

    // MARK: helpers

    private func decodeError(_ body: ByteBuffer?) -> ErrorEnvelope? {
        guard let body else { return nil }
        let data = Data(body.readableBytesView)
        return try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
    }

    /// Sign up via the API and return (response, decoded user).
    private func signUp(_ app: Application, email: String, password: String = "Abcdef12") async throws -> (XCTHTTPResponse, UserPublic?) {
        var captured: UserPublic? = nil
        var capturedRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/signup", beforeRequest: { req async throws in
            try req.content.encode(SignupRequest(email: email, password: password))
        }, afterResponse: { res async throws in
            capturedRes = res
            if res.status == .created {
                captured = try res.content.decode(SignupResponse.self).user
            }
        })
        return (capturedRes!, captured)
    }

    // MARK: signup

    func testSignupReturns201UnverifiedNoTokens() async throws {
        let (app, emailer) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }

        let (res, user) = try await signUp(app, email: "new@example.com")
        XCTAssertEqual(res.status, .created)
        XCTAssertEqual(user?.email, "new@example.com")
        XCTAssertEqual(user?.email_verified, false)
        XCTAssertEqual(emailer.captured.count, 1)
        XCTAssertEqual(emailer.captured[0].subjectKey, .verifyEmail)
    }

    func testSignupDuplicateReturns422EmailTaken() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        _ = try await signUp(app, email: "dup@example.com")

        var capturedRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/signup", beforeRequest: { req async throws in
            try req.content.encode(SignupRequest(email: "dup@example.com", password: "Abcdef12"))
        }, afterResponse: { res async throws in
            capturedRes = res
        })
        XCTAssertEqual(capturedRes?.status, .unprocessableEntity)
        XCTAssertEqual(decodeError(capturedRes?.body)?.error.code, "email_taken")
    }

    func testSignupWeakPasswordReturns422WithRules() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        var capturedRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/signup", beforeRequest: { req async throws in
            try req.content.encode(SignupRequest(email: "weak@example.com", password: "abcdefgh"))
        }, afterResponse: { res async throws in
            capturedRes = res
        })
        XCTAssertEqual(capturedRes?.status, .unprocessableEntity)
        let env = decodeError(capturedRes?.body)
        XCTAssertEqual(env?.error.code, "weak_password")
        XCTAssertNotNil(env?.error.details["rules"])
    }

    func testSignupInvalidBodyReturns400() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        var capturedRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/signup", beforeRequest: { req async throws in
            try req.content.encode(BlankBody(), as: .json)
        }, afterResponse: { res async throws in
            capturedRes = res
        })
        XCTAssertEqual(capturedRes?.status, .badRequest)
        XCTAssertEqual(decodeError(capturedRes?.body)?.error.code, "invalid_body")
    }

    // MARK: signin

    func testSigninBeforeVerifyReturns403EmailNotVerified() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        _ = try await signUp(app, email: "unverified@example.com")

        var capturedRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/signin", beforeRequest: { req async throws in
            try req.content.encode(SigninRequest(email: "unverified@example.com", password: "Abcdef12"))
        }, afterResponse: { res async throws in
            capturedRes = res
        })
        XCTAssertEqual(capturedRes?.status, .forbidden)
        XCTAssertEqual(decodeError(capturedRes?.body)?.error.code, "email_not_verified")
    }

    func testSigninBadPasswordReturns401InvalidCredentials() async throws {
        let (app, emailer) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        _ = try await signUp(app, email: "signin@example.com")
        let raw = emailer.rawToken(at: 0)!
        _ = try await app.test(.POST, "/api/v1/auth/verify-email", beforeRequest: { req async throws in
            try req.content.encode(VerifyEmailRequest(token: raw))
        })

        var capturedRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/signin", beforeRequest: { req async throws in
            try req.content.encode(SigninRequest(email: "signin@example.com", password: "wrongpass1"))
        }, afterResponse: { res async throws in
            capturedRes = res
        })
        XCTAssertEqual(capturedRes?.status, .unauthorized)
        XCTAssertEqual(decodeError(capturedRes?.body)?.error.code, "invalid_credentials")
    }

    func testSigninUnknownUserReturns401InvalidCredentials() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        var capturedRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/signin", beforeRequest: { req async throws in
            try req.content.encode(SigninRequest(email: "ghost@example.com", password: "Abcdef12"))
        }, afterResponse: { res async throws in
            capturedRes = res
        })
        XCTAssertEqual(capturedRes?.status, .unauthorized)
        XCTAssertEqual(decodeError(capturedRes?.body)?.error.code, "invalid_credentials")
    }

    // MARK: full happy-path flow

    func testFullFlowSignupVerifySigninRefreshLogoutMe() async throws {
        let (app, emailer) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }

        // signup
        _ = try await signUp(app, email: "flow@example.com")
        let verifyRaw = emailer.rawToken(at: 0)!

        // verify-email → 200 + tokens
        var verifyResponse: VerifyEmailResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/verify-email", beforeRequest: { req async throws in
            try req.content.encode(VerifyEmailRequest(token: verifyRaw))
        }, afterResponse: { res async throws in
            verifyResponse = try res.content.decode(VerifyEmailResponse.self)
        })
        XCTAssertEqual(verifyResponse?.user.email_verified, true)
        XCTAssertFalse(verifyResponse?.access_token.isEmpty ?? true)
        XCTAssertFalse(verifyResponse?.refresh_token.isEmpty ?? true)
        let refresh1 = verifyResponse!.refresh_token

        // signin → 200 + tokens
        var signinResponse: AuthTokenResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/signin", beforeRequest: { req async throws in
            try req.content.encode(SigninRequest(email: "flow@example.com", password: "Abcdef12"))
        }, afterResponse: { res async throws in
            signinResponse = try res.content.decode(AuthTokenResponse.self)
        })
        XCTAssertEqual(signinResponse?.user.email, "flow@example.com")
        let access = signinResponse!.access_token
        let refresh2 = signinResponse!.refresh_token

        // /me with bearer → 200 user
        var meRes: XCTHTTPResponse? = nil
        _ = try await app.test(.GET, "/api/v1/auth/me", headers: ["Authorization": "Bearer \(access)"], afterResponse: { res async throws in
            meRes = res
        })
        XCTAssertEqual(meRes?.status, .ok)
        let me = try meRes!.content.decode(UserPublic.self)
        XCTAssertEqual(me.email, "flow@example.com")

        // /me without bearer → 401
        var meNoAuth: XCTHTTPResponse? = nil
        _ = try await app.test(.GET, "/api/v1/auth/me", afterResponse: { res async throws in
            meNoAuth = res
        })
        XCTAssertEqual(meNoAuth?.status, .unauthorized)

        // refresh → rotated pair
        var refreshed: AuthTokenResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/refresh", beforeRequest: { req async throws in
            try req.content.encode(RefreshRequest(refresh_token: refresh2))
        }, afterResponse: { res async throws in
            refreshed = try res.content.decode(AuthTokenResponse.self)
        })
        XCTAssertNotEqual(refreshed?.refresh_token, refresh2)
        let refresh3 = refreshed!.refresh_token

        // reuse old refresh2 → 401 token_reuse
        var reuseRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/refresh", beforeRequest: { req async throws in
            try req.content.encode(RefreshRequest(refresh_token: refresh2))
        }, afterResponse: { res async throws in
            reuseRes = res
        })
        XCTAssertEqual(reuseRes?.status, .unauthorized)
        XCTAssertEqual(decodeError(reuseRes?.body)?.error.code, "token_reuse")

        // refresh3 also revoked.
        var reuseAgainRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/refresh", beforeRequest: { req async throws in
            try req.content.encode(RefreshRequest(refresh_token: refresh3))
        }, afterResponse: { res async throws in
            reuseAgainRes = res
        })
        XCTAssertEqual(reuseAgainRes?.status, .unauthorized)

        // logout with bearer + refresh
        var logoutRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/logout",
            headers: ["Authorization": "Bearer \(access)"],
            beforeRequest: { req async throws in
                try req.content.encode(RefreshRequest(refresh_token: refresh1))
            }, afterResponse: { res async throws in
                logoutRes = res
            })
        XCTAssertEqual(logoutRes?.status, .noContent)

        // logout without bearer → 401
        var logoutNoAuth: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/logout", beforeRequest: { req async throws in
            try req.content.encode(RefreshRequest(refresh_token: refresh1))
        }, afterResponse: { res async throws in
            logoutNoAuth = res
        })
        XCTAssertEqual(logoutNoAuth?.status, .unauthorized)
    }

    // MARK: verify-email errors

    func testVerifyEmailInvalidTokenReturns404() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        var capturedRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/verify-email", beforeRequest: { req async throws in
            try req.content.encode(VerifyEmailRequest(token: "bogus"))
        }, afterResponse: { res async throws in
            capturedRes = res
        })
        XCTAssertEqual(capturedRes?.status, .notFound)
        XCTAssertEqual(decodeError(capturedRes?.body)?.error.code, "verify_token_invalid")
    }

    func testVerifyEmailResendAlways200() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        var res1: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/verify-email/resend", beforeRequest: { req async throws in
            try req.content.encode(ResendVerificationRequest(email: "ghost@example.com"))
        }, afterResponse: { res async throws in res1 = res })
        XCTAssertEqual(res1?.status, .ok)

        _ = try await signUp(app, email: "resend@example.com")
        var res2: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/verify-email/resend", beforeRequest: { req async throws in
            try req.content.encode(ResendVerificationRequest(email: "resend@example.com"))
        }, afterResponse: { res async throws in res2 = res })
        XCTAssertEqual(res2?.status, .ok)
    }

    // MARK: password reset

    func testResetRequestReturns202Always() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        var res1: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/password/reset-request", beforeRequest: { req async throws in
            try req.content.encode(ResetRequestRequest(email: "ghost@example.com"))
        }, afterResponse: { res async throws in res1 = res })
        XCTAssertEqual(res1?.status, .accepted)

        _ = try await signUp(app, email: "reset@example.com")
        var res2: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/password/reset-request", beforeRequest: { req async throws in
            try req.content.encode(ResetRequestRequest(email: "reset@example.com"))
        }, afterResponse: { res async throws in res2 = res })
        XCTAssertEqual(res2?.status, .accepted)
    }

    func testResetConfirmFullFlow() async throws {
        let (app, emailer) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        _ = try await signUp(app, email: "resetflow@example.com")
        let verifyRaw = emailer.rawToken(at: 0)!
        _ = try await app.test(.POST, "/api/v1/auth/verify-email", beforeRequest: { req async throws in
            try req.content.encode(VerifyEmailRequest(token: verifyRaw))
        })

        // request reset
        emailer.reset()
        _ = try await app.test(.POST, "/api/v1/password/reset-request", beforeRequest: { req async throws in
            try req.content.encode(ResetRequestRequest(email: "resetflow@example.com"))
        })
        let resetRaw = emailer.captured.first(where: { $0.subjectKey == .passwordReset })!.linkURL
            .split(separator: "=").last.map(String.init)!

        // confirm
        var confirmRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/password/reset-confirm", beforeRequest: { req async throws in
            try req.content.encode(ResetConfirmRequest(token: resetRaw, new_password: "NewPass12"))
        }, afterResponse: { res async throws in confirmRes = res })
        XCTAssertEqual(confirmRes?.status, .noContent)

        // signin with new password works.
        var signinRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/signin", beforeRequest: { req async throws in
            try req.content.encode(SigninRequest(email: "resetflow@example.com", password: "NewPass12"))
        }, afterResponse: { res async throws in signinRes = res })
        XCTAssertEqual(signinRes?.status, .ok)

        // old password fails.
        var oldRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/signin", beforeRequest: { req async throws in
            try req.content.encode(SigninRequest(email: "resetflow@example.com", password: "Abcdef12"))
        }, afterResponse: { res async throws in oldRes = res })
        XCTAssertEqual(oldRes?.status, .unauthorized)
    }

    func testResetConfirmInvalidTokenReturns404() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        var capturedRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/password/reset-confirm", beforeRequest: { req async throws in
            try req.content.encode(ResetConfirmRequest(token: "bogus", new_password: "NewPass12"))
        }, afterResponse: { res async throws in capturedRes = res })
        XCTAssertEqual(capturedRes?.status, .notFound)
        XCTAssertEqual(decodeError(capturedRes?.body)?.error.code, "reset_token_invalid")
    }

    func testResetConfirmWeakPasswordReturns422() async throws {
        let (app, emailer) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        _ = try await signUp(app, email: "weak@example.com")
        let verifyRaw = emailer.rawToken(at: 0)!
        _ = try await app.test(.POST, "/api/v1/auth/verify-email", beforeRequest: { req async throws in
            try req.content.encode(VerifyEmailRequest(token: verifyRaw))
        })
        _ = try await app.test(.POST, "/api/v1/password/reset-request", beforeRequest: { req async throws in
            try req.content.encode(ResetRequestRequest(email: "weak@example.com"))
        })
        let resetRaw = emailer.captured.first(where: { $0.subjectKey == .passwordReset })!.linkURL
            .split(separator: "=").last.map(String.init)!

        var capturedRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/password/reset-confirm", beforeRequest: { req async throws in
            try req.content.encode(ResetConfirmRequest(token: resetRaw, new_password: "allletters"))
        }, afterResponse: { res async throws in capturedRes = res })
        XCTAssertEqual(capturedRes?.status, .unprocessableEntity)
        XCTAssertEqual(decodeError(capturedRes?.body)?.error.code, "weak_password")
    }

    // MARK: invalid body across endpoints

    func testSigninInvalidBodyReturns400() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        var capturedRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/signin", beforeRequest: { req async throws in
            try req.content.encode(BlankBody(), as: .json)
        }, afterResponse: { res async throws in capturedRes = res })
        XCTAssertEqual(capturedRes?.status, .badRequest)
        XCTAssertEqual(decodeError(capturedRes?.body)?.error.code, "invalid_body")
    }

    func testRefreshInvalidBodyReturns400() async throws {
        let (app, _) = try await TestApp.make()
        addTeardownBlock { try await app.asyncShutdown() }
        var capturedRes: XCTHTTPResponse? = nil
        _ = try await app.test(.POST, "/api/v1/auth/refresh", beforeRequest: { req async throws in
            try req.content.encode(BlankBody(), as: .json)
        }, afterResponse: { res async throws in capturedRes = res })
        XCTAssertEqual(capturedRes?.status, .badRequest)
    }
}