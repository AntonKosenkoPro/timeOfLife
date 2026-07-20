import Foundation
import SwiftUI

/// View model for the OTP entry screen.
///
/// Validates the code locally (6 digits), delegates verification to
/// `AuthService`, and handles magic-link deep link pre-fill + auto-submit.
@MainActor
final class OtpEntryViewModel: ObservableObject {
    @Published var code: String = ""
    @Published var fieldErrors: FieldErrors = .empty
    @Published var isLoading = false
    @Published var isVerified = false
    @Published var errorMessage: String?

    let email: String
    private let service: AuthService
    private let connectivity: Connectivity

    init(service: AuthService, connectivity: Connectivity, email: String) {
        self.service = service
        self.connectivity = connectivity
        self.email = email
    }

    /// Validates the OTP code and returns `true` if valid.
    func validateCode() -> Bool {
        let errors = AuthValidator.validateOtpCode(code)
        fieldErrors.otp = AuthValidator.unifiedOtpMessage(errors)
        return errors.isEmpty
    }

    /// Submits the OTP verification. Validates first; on success sets `isVerified`.
    func submit() async {
        guard connectivity.isConnected else {
            errorMessage = String.localized("error.offline")
            return
        }

        guard validateCode() else { return }

        isLoading = true
        errorMessage = nil

        do {
            try await service.verifyOtp(email: email, code: code)
            isVerified = true
        } catch let error as APIError {
            errorMessage = ErrorLocalization.message(for: error)
        } catch {
            errorMessage = String.localized("error.unknown")
        }

        isLoading = false
    }

    /// Handles a magic-link deep link code: pre-fills the field and auto-submits.
    func handleDeepLinkCode(_ code: String) {
        self.code = code
        Task {
            await submit()
        }
    }

    /// Resends the OTP code to the same email.
    func resendOtp() async {
        guard connectivity.isConnected else {
            errorMessage = String.localized("error.offline")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await service.requestOtp(email: email)
        } catch let error as APIError {
            errorMessage = ErrorLocalization.message(for: error)
        } catch {
            errorMessage = String.localized("error.unknown")
        }

        isLoading = false
    }

    /// Resets the form.
    func reset() {
        code = ""
        fieldErrors = .empty
        isLoading = false
        isVerified = false
        errorMessage = nil
    }
}
