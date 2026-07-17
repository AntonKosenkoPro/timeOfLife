import Foundation
import Vapor
import Fluent

/// Auth endpoints. Routes are registered by `Routes/routes.swift`; this file holds
/// the request handlers, wired through `Application.services`.
struct AuthController {
    let services: AppServices

    init(_ services: AppServices) { self.services = services }

    // MARK: POST /auth/signup
    func signup(_ req: Request) async throws -> Response {
        let input: SignupRequest
        do {
            input = try req.content.decode(SignupRequest.self)
        } catch {
            return AuthError.invalidBody.makeResponse(req)
        }
        do {
            let lang = EmailLanguage.from(acceptLanguage: req.headers.first(name: .acceptLanguage))
            let user = try await services.auth.signUp(
                email: input.email,
                password: input.password,
                language: lang,
                on: req.db
            )
            let body = SignupResponse(user: UserPublic(user))
            let resp = Response(status: .created)
            try resp.content.encode(body)
            return resp
        } catch let e as Abortable {
            return e.makeResponse(req)
        } catch {
            req.logger.error("signup unexpected: \(error)")
            return AuthError.invalidBody.makeResponse(req)
        }
    }

    // MARK: POST /auth/verify-email
    func verifyEmail(_ req: Request) async throws -> Response {
        let input: VerifyEmailRequest
        do {
            input = try req.content.decode(VerifyEmailRequest.self)
        } catch {
            return AuthError.invalidBody.makeResponse(req)
        }
        do {
            let (user, access, refresh) = try await services.emails.verify(rawToken: input.token, on: req.db)
            let body: Content = VerifyEmailResponse(
                user: UserPublic(user),
                access_token: access,
                refresh_token: refresh
            )
            let resp = Response(status: .ok)
            try resp.content.encode(body)
            return resp
        } catch let e as Abortable {
            return e.makeResponse(req)
        } catch {
            req.logger.error("verify unexpected: \(error)")
            return VerifyError.tokenInvalid.makeResponse(req)
        }
    }

    // MARK: POST /auth/verify-email/resend
    func resendVerification(_ req: Request) async throws -> Response {
        let input: ResendVerificationRequest
        do {
            input = try req.content.decode(ResendVerificationRequest.self)
        } catch {
            return AuthError.invalidBody.makeResponse(req)
        }
        do {
            let lang = EmailLanguage.from(acceptLanguage: req.headers.first(name: .acceptLanguage))
            _ = try await services.emails.resend(email: input.email, language: lang, on: req.db)
            // Always 200 (no enumeration).
            let resp = Response(status: .ok)
            try resp.content.encode(MessageResponse(message: "If the account exists and is unverified, a verification email has been sent."))
            return resp
        } catch let e as Abortable {
            return e.makeResponse(req)
        } catch {
            req.logger.error("resend unexpected: \(error)")
            return AuthError.invalidBody.makeResponse(req)
        }
    }

    // MARK: POST /auth/signin
    func signin(_ req: Request) async throws -> Response {
        let input: SigninRequest
        do {
            input = try req.content.decode(SigninRequest.self)
        } catch {
            return AuthError.invalidBody.makeResponse(req)
        }
        do {
            let deviceId = req.headers.first(name: "X-Device-Id")
            let userAgent = req.headers.first(name: .userAgent)
            let (access, refresh, user) = try await services.auth.signIn(
                email: input.email,
                password: input.password,
                deviceId: deviceId,
                userAgent: userAgent,
                on: req
            )
            let body = AuthTokenResponse(
                access_token: access,
                refresh_token: refresh,
                user: UserPublic(user)
            )
            // Ignore lang var (kept for future localized error responses).
            let resp = Response(status: .ok)
            try resp.content.encode(body)
            return resp
        } catch let e as Abortable {
            return e.makeResponse(req)
        } catch {
            req.logger.error("signin unexpected: \(error)")
            return AuthError.invalidCredentials.makeResponse(req)
        }
    }

    // MARK: POST /auth/refresh
    func refresh(_ req: Request) async throws -> Response {
        let input: RefreshRequest
        do {
            input = try req.content.decode(RefreshRequest.self)
        } catch {
            return AuthError.invalidBody.makeResponse(req)
        }
        do {
            let (access, refresh, user) = try await services.auth.refresh(rawOld: input.refresh_token, on: req.db)
            let body = AuthTokenResponse(
                access_token: access,
                refresh_token: refresh,
                user: UserPublic(user)
            )
            let resp = Response(status: .ok)
            try resp.content.encode(body)
            return resp
        } catch let e as Abortable {
            return e.makeResponse(req)
        } catch {
            req.logger.error("refresh unexpected: \(error)")
            return AuthError.invalidRefresh.makeResponse(req)
        }
    }

    // MARK: POST /auth/logout  (Bearer required)
    func logout(_ req: Request) async throws -> Response {
        guard let user = req.auth.get(User.self) else {
            return AuthError.unauthorized.makeResponse(req)
        }
        let input: RefreshRequest
        do {
            input = try req.content.decode(RefreshRequest.self)
        } catch {
            return AuthError.invalidBody.makeResponse(req)
        }
        do {
            try await services.auth.logout(raw: input.refresh_token, on: req.db)
            _ = user
            return Response(status: .noContent)
        } catch let e as Abortable {
            return e.makeResponse(req)
        } catch {
            req.logger.error("logout unexpected: \(error)")
            return AuthError.invalidRefresh.makeResponse(req)
        }
    }

    // MARK: GET /auth/me  (Bearer required)
    func me(_ req: Request) async throws -> Response {
        guard let user = req.auth.get(User.self) else {
            return AuthError.unauthorized.makeResponse(req)
        }
        let body = UserPublic(user)
        let resp = Response(status: .ok)
        try resp.content.encode(body)
        return resp
    }
}