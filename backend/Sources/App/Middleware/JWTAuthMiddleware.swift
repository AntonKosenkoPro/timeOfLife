import Foundation
import Vapor
import Fluent
import JWTKit
import JWT

/// Verifies Bearer access token and loads the authenticated user onto `req.auth`.
/// On failure responds with our error envelope (401 `unauthorized`).
struct JWTAuthMiddleware: AsyncMiddleware {
    let tokens: TokenService

    init(tokens: TokenService) { self.tokens = tokens }

    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let bearer = req.headers.bearerAuthorization else {
            return AuthError.unauthorized.makeResponse(req)
        }
        do {
            let claims = try await tokens.verifyAccessToken(bearer.token)
            guard let uuid = UUID(uuidString: claims.sub.value) else {
                return AuthError.unauthorized.makeResponse(req)
            }
            guard let user = try await User.find(uuid, on: req.db) else {
                return AuthError.unauthorized.makeResponse(req)
            }
            req.auth.login(user)
        } catch {
            return AuthError.unauthorized.makeResponse(req)
        }
        return try await next.respond(to: req)
    }
}