import Foundation
import Fluent

struct CreateEmailVerificationTokens: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema("email_verification_tokens")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("token_hash", .string, .required)
            .field("expires_at", .datetime, .required)
            .field("used", .bool, .required)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()
    }

    func revert(on db: Database) async throws {
        try await db.schema("email_verification_tokens").delete()
    }
}