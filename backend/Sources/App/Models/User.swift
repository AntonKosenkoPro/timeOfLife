import Foundation
import Fluent
import Vapor

final class User: Model, @unchecked Sendable, Authenticatable {
    static let schema = "users"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "email")
    var email: String

    @Field(key: "password_hash")
    var passwordHash: String

    @Field(key: "email_verified_at")
    var emailVerifiedAt: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @Children(for: \.$user)
    var refreshTokens: [RefreshToken]

    init() {}

    init(
        id: UUID? = nil,
        email: String,
        passwordHash: String,
        emailVerifiedAt: Date? = nil
    ) {
        self.id = id
        self.email = email
        self.passwordHash = passwordHash
        self.emailVerifiedAt = emailVerifiedAt
    }

    var isEmailVerified: Bool { emailVerifiedAt != nil }
}