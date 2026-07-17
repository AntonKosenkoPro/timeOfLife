import Foundation
import Combine

@MainActor
final class ForgotPasswordViewModel: AuthViewModelBase {
    @Published var email: String = ""
    var onSuccess: (() -> Void)?

    override init(service: AuthService, connectivity: Connectivity) {
        super.init(service: service, connectivity: connectivity)
    }

    func submit() async {
        resetTransient()
        let emailErrors = AuthValidator.validateEmail(email)
        if !emailErrors.isEmpty {
            fieldErrors = FieldErrors(email: emailErrors.map { $0.text }, password: [])
            return
        }
        guard !isOffline else {
            submitError = NSLocalizedString("error.offline", comment: "")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await service.requestPasswordReset(email: email)
            successMessage = NSLocalizedString("forgot.success", comment: "")
            onSuccess?()
        } catch let error as APIError {
            _ = mapServer(error: error)
        } catch {
            submitError = NSLocalizedString("error.unknown", comment: "")
        }
    }

    // reset-request always returns 202; rate_limited / invalid_body map to
    // top-level submitError via the base.
}