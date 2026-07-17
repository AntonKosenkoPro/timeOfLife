import Foundation
import Fluent

final class RefreshToken: Model, @unchecked Sendable {
    static let schema = "refresh_tokens"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "token_hash")
    var tokenHash: String

    @Field(key: "device_id")
    var deviceId: String?

    @Field(key: "user_agent")
    var userAgent: String?

    @Field(key: "expires_at")
    var expiresAt: Date

    @Field(key: "revoked")
    var revoked: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: UUID,
        tokenHash: String,
        deviceId: String? = nil,
        userAgent: String? = nil,
        expiresAt: Date,
        revoked: Bool = false
    ) {
        self.id = id
        self.$user.id = userID
        self.tokenHash = tokenHash
        self.deviceId = deviceId
        self.userAgent = userAgent
        self.expiresAt = expiresAt
        self.revoked = revoked
    }
}