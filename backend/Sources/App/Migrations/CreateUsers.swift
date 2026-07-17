import Foundation
import Fluent
import Vapor

struct CreateUsers: AsyncMigration {
    func prepare(on db: Database) async throws {
        try await db.schema("users")
            .id()
            .field("email", .string, .required)
            .field("password_hash", .string, .required)
            .field("email_verified_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "email")
            .create()
    }

    func revert(on db: Database) async throws {
        try await db.schema("users").delete()
    }
}