import Foundation
import Vapor

/// In-memory token-bucket rate limiter middleware. Keys on IP (+ optional email when available).
/// On throttle, responds 429 with `Retry-After` and our error envelope.
struct RateLimitMiddleware: AsyncMiddleware {
    let limiter: RateLimiter
    let scope: String  // e.g. "signin", "signup"

    init(limiter: RateLimiter, scope: String) {
        self.limiter = limiter
        self.scope = scope
    }

    func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let ip = req.remoteAddress?.ipAddress ?? "unknown"
        let key = "\(scope):\(ip)"
        if let retryAfter = await limiter.tryConsume(key) {
            let error = RateLimitError.throttled(retryAfter: retryAfter)
            let response = error.makeResponse(req)
            response.headers.add(name: "Retry-After", value: "\(retryAfter)")
            return response
        }
        return try await next.respond(to: req)
    }
}