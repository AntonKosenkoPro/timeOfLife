import Foundation
import Vapor
import Fluent

/// Password-reset endpoints.
struct PasswordResetController {
    let services: AppServices

    init(_ services: AppServices) { self.services = services }

    // MARK: POST /password/reset-request
    func resetRequest(_ req: Request) async throws -> Response {
        let input: ResetRequestRequest
        do {
            input = try req.content.decode(ResetRequestRequest.self)
        } catch {
            return AuthError.invalidBody.makeResponse(req)
        }
        do {
            let lang = EmailLanguage.from(acceptLanguage: req.headers.first(name: .acceptLanguage))
            _ = try await services.passwordReset.requestReset(email: input.email, language: lang, on: req.db)
            // Always 202 — no enumeration.
            return Response(status: .accepted)
        } catch let e as Abortable {
            return e.makeResponse(req)
        } catch {
            req.logger.error("reset-request unexpected: \(error)")
            return Response(status: .accepted)
        }
    }

    // MARK: POST /password/reset-confirm
    func resetConfirm(_ req: Request) async throws -> Response {
        let input: ResetConfirmRequest
        do {
            input = try req.content.decode(ResetConfirmRequest.self)
        } catch {
            return AuthError.invalidBody.makeResponse(req)
        }
        do {
            try await services.passwordReset.confirmReset(
                rawToken: input.token,
                newPassword: input.new_password,
                on: req.db
            )
            return Response(status: .noContent)
        } catch let e as Abortable {
            return e.makeResponse(req)
        } catch {
            req.logger.error("reset-confirm unexpected: \(error)")
            return ResetError.tokenInvalid.makeResponse(req)
        }
    }
}