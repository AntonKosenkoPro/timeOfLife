import Foundation
import Vapor

// MARK: - Auth request DTOs

struct SignupRequest: Content {
    let email: String
    let password: String
}

struct SigninRequest: Content {
    let email: String
    let password: String
}

struct RefreshRequest: Content {
    let refresh_token: String
}

struct VerifyEmailRequest: Content {
    let token: String
}

struct ResendVerificationRequest: Content {
    let email: String
}

// MARK: - Auth response DTOs

struct UserPublic: Content {
    let id: UUID
    let email: String
    let email_verified: Bool

    init(_ user: User) {
        self.id = user.id!
        self.email = user.email
        self.email_verified = user.emailVerifiedAt != nil
    }
}

struct SignupResponse: Content {
    let user: UserPublic
}

struct AuthTokenResponse: Content {
    let access_token: String
    let refresh_token: String
    let user: UserPublic
}

struct VerifyEmailResponse: Content {
    let user: UserPublic
    let access_token: String
    let refresh_token: String
}

struct MessageResponse: Content {
    let message: String
}