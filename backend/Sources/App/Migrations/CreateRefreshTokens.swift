import Foundation
import Fluent

struct CreateRefreshTokens: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema("refresh_tokens")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("token_hash", .string, .required)
            .field("device_id", .string)
            .field("user_agent", .string)
            .field("expires_at", .datetime, .required)
            .field("revoked", .bool, .required)
            .field("created_at", .datetime)
            .unique(on: "token_hash")
            .create()
    }

    func revert(on db: Database) async throws {
        try await db.schema("refresh_tokens").delete()
    }
}