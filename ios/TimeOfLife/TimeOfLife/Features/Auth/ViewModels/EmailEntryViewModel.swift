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
    private let appleService: AppleSignInService

    /// `appleService` defaults to a real `AppleSignInService` so existing call
    /// sites (and previews) keep working; tests inject one wrapping a fake
    /// `AppleAuthorizationProviding`.
    init(
        service: AuthService,
        connectivity: Connectivity,
        appleService: AppleSignInService = AppleSignInService()
    ) {
        self.service = service
        self.connectivity = connectivity
        self.appleService = appleService
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

    /// Initiates Sign in with Apple. Runs the Apple authorization, then exchanges
    /// the identity token for a session via `AuthService`. Cancellation is silent
    /// (no error banner); other failures surface `appleSignIn.error`.
    func signInWithApple() async {
        guard connectivity.isConnected else {
            errorMessage = String.localized("error.offline")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let credential = try await appleService.signIn()
            try await service.signInWithApple(identityToken: credential.identityToken)
        } catch AppleSignInError.canceled {
            // User dismissed the Apple sheet — no error.
        } catch let error as APIError {
            errorMessage = ErrorLocalization.message(for: error)
        } catch {
            errorMessage = L10n.appleSignInError.text
        }

        isLoading = false
    }
}
