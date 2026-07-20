import Foundation
import SwiftUI

/// View model for the email entry screen.
///
/// Validates the email locally before hitting the network, normalizes it
/// (trim + lowercase), and delegates the request to `AuthService`.
@MainActor
final class EmailEntryViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var fieldErrors: FieldErrors = .empty
    @Published var isLoading = false
    @Published var isEmailSent = false
    @Published var errorMessage: String?

    private let service: AuthService
    private let connectivity: Connectivity

    init(service: AuthService, connectivity: Connectivity) {
        self.service = service
        self.connectivity = connectivity
    }

    /// Validates the email field and returns `true` if valid.
    func validateEmail() -> Bool {
        let errors = AuthValidator.validateEmail(email)
        fieldErrors.email = AuthValidator.unifiedEmailMessage(errors)
        return errors.isEmpty
    }

    /// Submits the OTP request. Validates first; on success sets `isEmailSent`.
    func submit() async {
        guard connectivity.isConnected else {
            errorMessage = String.localized("error.offline")
            return
        }

        guard validateEmail() else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await service.requestOtp(email: email)
            isEmailSent = true
        } catch let error as APIError {
            errorMessage = ErrorLocalization.message(for: error)
        } catch {
            errorMessage = String.localized("error.unknown")
        }

        isLoading = false
    }

    /// Resets the form to its initial state.
    func reset() {
        email = ""
        fieldErrors = .empty
        isLoading = false
        isEmailSent = false
        errorMessage = nil
    }
}
