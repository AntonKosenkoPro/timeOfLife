import Foundation
import Combine

@MainActor
final class SignInViewModel: AuthViewModelBase {
    @Published var email: String = ""
    @Published var password: String = ""
    var onSuccess: (() -> Void)?

    override init(service: AuthService, connectivity: Connectivity) {
        super.init(service: service, connectivity: connectivity)
    }

    func submit() async {
        resetTransient()
        let emailErrors = AuthValidator.validateEmail(email)
        let passwordErrors = AuthValidator.validatePassword(password)
        if !emailErrors.isEmpty || !passwordErrors.isEmpty {
            fieldErrors = FieldErrors(
                email: emailErrors.map { $0.text },
                password: passwordErrors.map { $0.text }
            )
            return
        }
        guard !isOffline else {
            submitError = NSLocalizedString("error.offline", comment: "")
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await service.signIn(email: email, password: password)
            successMessage = NSLocalizedString("signin.success", comment: "")
            onSuccess?()
        } catch let error as APIError {
            _ = mapServer(error: error)
        } catch {
            submitError = NSLocalizedString("error.unknown", comment: "")
        }
    }

    override func mapServer(error: APIError) -> Bool {
        // Sign-in uses generic invalid_credentials; never reveal which field.
        if case let .server(code, _, _) = error, code == "invalid_credentials" {
            submitError = NSLocalizedString("error.invalid_credentials", comment: "")
            return false
        }
        return super.mapServer(error: error)
    }
}