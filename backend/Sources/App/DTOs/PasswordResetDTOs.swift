import Foundation
import Vapor

struct ResetRequestRequest: Content {
    let email: String
}

struct ResetConfirmRequest: Content {
    let token: String
    let new_password: String
}