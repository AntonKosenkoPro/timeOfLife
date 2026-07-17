import Foundation
import Combine

@MainActor
final class VerifyEmailViewModel: AuthViewModelBase {
    @Published var token: String
    var onSuccess: (() -> Void)?

    init(service: AuthService, connectivity: Connectivity, token: String = "") {
        self.token = token
        super.init(service: service, connectivity: connectivity)
    }

    func submit() async {
        resetTransient()
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            submitError = NSLocalizedString("error.verify_token_invalid", comment: "")
            return
        }
        guard !isOffline else {
            submitError = NSLocalizedString("error.offline", comment: "")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await service.verifyEmail(token: token)
            successMessage = NSLocalizedString("verify.success", comment: "")
            onSuccess?()
        } catch let error as APIError {
            _ = mapServer(error: error)
        } catch {
            submitError = NSLocalizedString("error.unknown", comment: "")
        }
    }

    func resend() async {
        // Resend uses the cached email from signup, if any.
        guard let email = service.sessionStore.cachedEmail, !email.isEmpty else {
            submitError = NSLocalizedString("error.invalid_body", comment: "")
            return
        }
        guard !isOffline else {
            submitError = NSLocalizedString("error.offline", comment: "")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await service.resendVerification(email: email)
            successMessage = NSLocalizedString("verify.resent", comment: "")
        } catch let error as APIError {
            _ = mapServer(error: error)
        } catch {
            submitError = NSLocalizedString("error.unknown", comment: "")
        }
    }
}